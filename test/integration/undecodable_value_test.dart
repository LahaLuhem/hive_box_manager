// One undecodable record must not poison a whole-box or scan read. The eager axis is pinned here too,
// where the open itself fails inside hive_ce and only delete-then-compact gets you back.
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../support/support.dart';

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
  useTempHive('hbm_undecodable_');

  setUpAll(() => Hive.registerAdapter(const FlakyThingAdapter()));

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

  feature('an eager read-all names the key that failed to decode', () {
    /// Written as `String` and reopened as `int`, so hive opens fine and the identity codec's cast is
    /// what refuses. Anything the adapter itself rejects takes the whole open down first.
    Future<void> seedMistyped() async {
      final wrote = await KeyedBox.open<String, int>('mixed').run();
      await wrote.put(1, 'one').run();
      await wrote.put(2, 'two').run();
      await Hive.close();
    }

    scenario('the failure names its key instead of surfacing a bare cast error', () async {
      await seedMistyped();
      final box = await KeyedBox.open<int, int>('mixed').run();

      final failure = await captureUndecodable(() async => box.values.toList());

      check(failure.boxName).equals('mixed');
      check(failure.key).equals(1);
      check(failure.cause).isA<TypeError>();
    });

    scenario('a box whose values all decode reads through untouched', () async {
      final wrote = await KeyedBox.open<String, int>('fine').run();
      await wrote.put(1, 'one').run();
      await wrote.put(2, 'two').run();
      await Hive.close();

      final box = await KeyedBox.open<String, int>('fine').run();

      check(box.values.toList()).deepEquals(['one', 'two']);
      // Twice on purpose: the view tracks its position per iteration.
      check(box.values.toList()).deepEquals(['one', 'two']);
    });
  });

  feature('a watch event names the key whose value failed to decode', () {
    /// 2 handles disagreeing about the value type. The writer stores a `String`, the watcher wants
    /// an `int`, so the codec refuses on the way through the stream.
    scenario('the stream error names the key rather than a bare cast error', () async {
      final writer = await KeyedBox.open<String, int>('watched').run();
      final watcher = await KeyedBox.open<int, int>('watched').run();

      final events = <TypedBoxEvent<int, int>>[];
      final failures = <Object>[];
      final subscription = watcher.watch().listen(events.add, onError: failures.add);
      await writer.put(7, 'seven').run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).isEmpty();
      check(failures).length.equals(1);
      final failure = failures.single as UndecodableValueException;
      check(failure.key).equals(7);
      check(failure.cause).isA<TypeError>();
    });

    scenario('a matching handle still receives its events untouched', () async {
      final box = await KeyedBox.open<String, int>('agreed').run();

      final events = <String>[];
      final subscription = box.watch().listen((event) => events.add(event.value));
      await box.put(7, 'seven').run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(['seven']);
    });
  });

  feature('a collection whose elements are not the box type fails at the read', () {
    /// `String` elements on disk, read back by boxes that want `int` ones.
    Future<void> seedMistyped() async {
      await (await ListBox.open<String, int>('lists').run()).put(1, ['one']).run();
      await (await SetBox.open<String, int>('sets').run()).put(1, ['one']).run();
      await Hive.close();
    }

    scenarioOutline<Future<Object?> Function()>(
      'a whole-box read names the key',
      examples: {
        'ListBox': () async => (await ListBox.open<int, int>('lists').run()).values.toList(),
        'LazyListBox': () => LazyListBox<int, int>('lists').values.run(),
        'SetBox': () async => (await SetBox.open<int, int>('sets').run()).values.toList(),
        'LazySetBox': () => LazySetBox<int, int>('sets').values.run(),
      },
      outline: (readAll) async {
        await seedMistyped();

        final failure = await captureUndecodable(readAll);

        check(failure.key).equals(1);
        check(failure.cause).isA<TypeError>();
      },
    );

    scenarioOutline<Future<Object?> Function()>(
      'a single-key read fails at the read, not when an element is touched',
      examples: {
        'ListBox': () async => (await ListBox.open<int, int>('lists').run()).get(1),
        'LazyListBox': () => LazyListBox<int, int>('lists').get(1).run(),
        'SetBox': () async => (await SetBox.open<int, int>('sets').run()).get(1),
        'LazySetBox': () => LazySetBox<int, int>('sets').get(1).run(),
      },
      outline: (read) async {
        await seedMistyped();

        // Already scoped to one record, so it surfaces unwrapped.
        check(await thrownBy(read)).isA<TypeError>();
      },
    );

    scenarioOutline<({Future<Stream<Object?>> Function() watch, Future<void> Function() write})>(
      'a watch event names the key',
      examples: {
        'ListBox': (
          watch: () async => (await ListBox.open<int, int>('lists').run()).watch(),
          write: () async => (await ListBox.open<String, int>('lists').run()).put(7, ['x']).run(),
        ),
        'LazyListBox': (
          watch: () async {
            final box = LazyListBox<int, int>('lists');
            await box.ensureInitialised().run();

            return box.watch();
          },
          write: () => LazyListBox<String, int>('lists').put(7, ['x']).run(),
        ),
        'SetBox': (
          watch: () async => (await SetBox.open<int, int>('sets').run()).watch(),
          write: () async => (await SetBox.open<String, int>('sets').run()).put(7, ['x']).run(),
        ),
        'LazySetBox': (
          watch: () async {
            final box = LazySetBox<int, int>('sets');
            await box.ensureInitialised().run();

            return box.watch();
          },
          write: () => LazySetBox<String, int>('sets').put(7, ['x']).run(),
        ),
      },
      outline: (handles) async {
        final failures = <Object>[];
        final subscription = (await handles.watch()).listen(null, onError: failures.add);
        await pumpEventQueue();
        await handles.write();
        await pumpEventQueue();
        await subscription.cancel();

        check(failures).length.equals(1);
        final failure = failures.single as UndecodableValueException;
        check(failure.key).equals(7);
        check(failure.cause).isA<TypeError>();
      },
    );
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
      // delete only appends a tombstone, so the bad frame stays until the file is rewritten.
      await lazy.compact().run();
      await lazy.close().run();

      final eager = await KeyedBox.open<Thing, String>('probeBox').run();

      check(eager.keys).deepEquals(['a', 'c']);
      check(eager.values.map((thing) => thing.id)).deepEquals(['a', 'c']);
    });
  });
}
