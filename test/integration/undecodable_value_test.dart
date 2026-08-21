// One undecodable record must not poison a whole-box or scan read. The eager axis is pinned here
// too: its open fails inside hive_ce, so only delete-then-compact recovers it.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../support/bdd.dart';
import '../support/codecs/date_key_codec.dart';
import '../support/doubles/flaky_thing_adapter.dart';
import '../support/doubles/recording_box_observer.dart';

/// Returns the [UndecodableValueException] [act] must raise, so scenarios assert key and cause.
Future<UndecodableValueException> captureUndecodable(Future<Object?> Function() act) async {
  try {
    await act();
  } on UndecodableValueException catch (failure) {
    return failure;
  }

  throw StateError('expected an UndecodableValueException, but the read succeeded');
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_undecodable_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(thingTypeId)) Hive.registerAdapter(FlakyThingAdapter());
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  /// Lays down a good, a bad and a good record, then closes so the next read comes off disk.
  Future<void> seedKeyed() async {
    final box = LazyKeyedBox<Thing, String>('probeBox');
    await box.put('a', const Thing('a')).run();
    await box.put('b', const Thing(undecodableId)).run();
    await box.put('c', const Thing('c')).run();
    await Hive.close();
  }

  feature('a whole-box read with one undecodable record', () {
    scenario('names the offending key and keeps the codec error as the cause', () async {
      await seedKeyed();
      final box = LazyKeyedBox<Thing, String>('probeBox');

      final failure = await captureUndecodable(() => box.values.run());

      check(failure.boxName).equals('probeBox');
      check(failure.key).equals('b');
      check(failure.cause).isA<FormatException>();
      check(failure.toString()).contains('key: b');
    });

    scenario('leaves every other record reachable through a single-key read', () async {
      await seedKeyed();
      final box = LazyKeyedBox<Thing, String>('probeBox');

      check((await box.get('a').run()).toNullable()?.id).equals('a');
      check((await box.get('c').run()).toNullable()?.id).equals('c');
      // Already scoped to one record, so it surfaces unwrapped.
      await check(box.get('b').run()).throws<FormatException>();
    });

    scenario('reports a value fault the observer can tell from a box fault', () async {
      await seedKeyed();
      final observer = RecordingBoxObserver();
      final box = LazyKeyedBox<Thing, String>('probeBox', observer: observer);

      await captureUndecodable(() => box.values.run());

      check(observer.calls).contains('error:probeBox:values:UndecodableValueException');
    });

    scenario('does not touch a box whose records all decode', () async {
      final seeded = LazyKeyedBox<Thing, String>('cleanBox');
      await seeded.put('a', const Thing('a')).run();
      await seeded.put('c', const Thing('c')).run();
      await Hive.close();

      final box = LazyKeyedBox<Thing, String>('cleanBox');

      check((await box.values.run()).map((thing) => thing.id)).deepEquals(['a', 'c']);
    });
  });

  feature("the reported key is the consumer's, not hive's stored form", () {
    scenario('a custom key codec reports the decoded key', () async {
      final stamp = DateTime.utc(2026, 8, 21);
      final seeded = LazyKeyedBox<Thing, DateTime>('dated', codec: const DateKeyCodec());
      await seeded.put(stamp, const Thing(undecodableId)).run();
      await Hive.close();

      final box = LazyKeyedBox<Thing, DateTime>('dated', codec: const DateKeyCodec());
      final failure = await captureUndecodable(() => box.values.run());

      // Not the ISO-8601 string hive stores under.
      check(failure.key).equals(stamp);
    });

    scenario('a dual scan reports the composite key and spares the other scans', () async {
      final seeded = LazyDualKeyBox<Thing, int, int>('dual');
      await seeded.put(1, 1, const Thing('a')).run();
      await seeded.put(1, 2, const Thing(undecodableId)).run();
      await seeded.put(2, 1, const Thing('c')).run();
      await Hive.close();

      final box = LazyDualKeyBox<Thing, int, int>('dual');
      final failure = await captureUndecodable(() => box.queryByPrimary(1).run());

      check(failure.key).equals((1, 2));
      // Failure is per-scan, not per-box: scans that miss the bad record still serve.
      check((await box.queryByPrimary(2).run()).map((thing) => thing.id)).deepEquals(['c']);
      check((await box.queryBySecondary(1).run()).map((thing) => thing.id)).deepEquals(['a', 'c']);
    });
  });

  feature('the eager axis still cannot open over an undecodable record', () {
    scenario('the open fails inside hive, before the package holds a box', () async {
      await seedKeyed();

      // Unwrapped: hive decodes every frame during openBox, so there is no per-value seam here.
      await check(KeyedBox.open<Thing, String>('probeBox').run()).throws<FormatException>();
      check(Hive.isBoxOpen('probeBox')).isFalse();
    });

    scenario('deleting the bad record then compacting restores the eager open', () async {
      await seedKeyed();

      final lazy = LazyKeyedBox<Thing, String>('probeBox');
      await lazy.delete('b').run();
      // delete only appends a tombstone; the bad frame stays until the file is rewritten.
      await lazy.compact().run();
      await lazy.close().run();

      final eager = await KeyedBox.open<Thing, String>('probeBox').run();

      check(eager.keys).deepEquals(['a', 'c']);
      check(eager.values.map((thing) => thing.id)).deepEquals(['a', 'c']);
    });
  });
}
