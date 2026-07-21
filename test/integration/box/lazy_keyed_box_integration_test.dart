// The lazy façade end to end against real hive_ce on temp dirs, through the public barrel:
// auto-open, TaskOption-shaped reads, disk truth across close + a new instance, the
// pre-first-use close() no-op (never creates the box), cipher pass-through, and the sync
// inspector carve-out against the real keystore.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/recording_box_observer.dart';

/// AES-256 wants exactly this many key bytes.
const aesKeyBytes = 32;

/// Collects the events [stream] emits while [act] runs, draining the event queue before
/// returning so no in-flight notification is missed.
Future<List<LazyTypedBoxEvent<String, int>>> record(
  Stream<LazyTypedBoxEvent<String, int>> stream,
  Future<void> Function() act,
) async {
  final events = <LazyTypedBoxEvent<String, int>>[];
  final subscription = stream.listen(events.add);
  await act();
  await pumpEventQueue();
  await subscription.cancel();

  return events;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_lazy_keyed_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('LazyKeyedBox auto-open against real hive', () {
    scenario('construction touches nothing; the first effect opens the real box', () async {
      final observer = RecordingBoxObserver();
      final box = LazyKeyedBox<String, int>('logs', observer: observer);

      check(Hive.isBoxOpen('logs')).isFalse();
      check(observer.calls).isEmpty();

      await box.put(7, 'v').run();

      check(Hive.isBoxOpen('logs')).isTrue();
      check(observer.calls).deepEquals(['opened:logs', 'written:logs:7:v']);
    });

    scenario('ensureInitialised warms the box up compositionally', () async {
      final box = LazyKeyedBox<String, int>('logs');

      await box.ensureInitialised().run();

      check(Hive.isBoxOpen('logs')).isTrue();
      check(box.isEmpty).isTrue();
    });

    scenario('the sync inspectors throw StateError before open, then read the keystore', () async {
      final box = LazyKeyedBox<String, int>('logs');

      check(() => box.length).throws<StateError>();
      check(() => box.keys).throws<StateError>();

      await box.putAll({1: 'a', 2: 'b'}).run();

      check(box.length).equals(2);
      check(box.keys).deepEquals([1, 2]);
      check(box.contains(1)).isTrue();
      check(box.isNotEmpty).isTrue();
    });
  });

  feature('LazyKeyedBox CRUD against real hive', () {
    scenario('every read and write member round-trips', () async {
      final box = LazyKeyedBox<String, int>('logs');

      await box.put(1, 'a').run();
      await box.putAll({2: 'b', 3: 'c'}).run();

      check((await box.get(1).run()).toNullable()).equals('a');
      check((await box.get(9).run()).isNone()).isTrue();
      check(await box.getOr(9, 'fallback').run()).equals('fallback');
      check(await box.values.run()).deepEquals(['a', 'b', 'c']);

      check(await box.update(1, (value) => '$value!').run()).equals('a!');
      check(await box.update(9, (value) => value, ifAbsent: () => 'seed').run()).equals('seed');
      await check(box.update(8, (value) => value).run()).throws<ArgumentError>();

      await box.delete(1).run();
      await box.deleteAll([2, 3]).run();
      await box.clear().run();

      check(box.isEmpty).isTrue();
    });

    scenario('values persist across close and a new instance (disk truth)', () async {
      final first = LazyKeyedBox<String, int>('logs');
      await first.put(7, 'persisted').run();
      await first.close().run();

      final second = LazyKeyedBox<String, int>('logs');

      check((await second.get(7).run()).toNullable()).equals('persisted');
    });

    scenario('an encrypted box reads back with the same cipher', () async {
      final cipher = HiveAesCipher(List.filled(aesKeyBytes, 7));
      final first = LazyKeyedBox<String, int>('secret', cipher: cipher);
      await first.put(1, 'ciphered').run();
      await first.close().run();

      final second = LazyKeyedBox<String, int>('secret', cipher: cipher);

      check((await second.get(1).run()).toNullable()).equals('ciphered');
    });

    scenario('the corruption gate rejects bad keys before the box even opens', () {
      final box = LazyKeyedBox<String, int>('logs');

      check(() => box.put(-1, 'v')).throws<ArgumentError>();

      check(Hive.isBoxOpen('logs')).isFalse();
    });
  });

  feature('LazyKeyedBox watch against real hive', () {
    scenario('writes carry Some, deletes carry None (lazy promise)', () async {
      final box = LazyKeyedBox<String, int>('logs');
      await box.ensureInitialised().run();

      final events = await record(box.watch(), () async {
        await box.put(7, 'v').run();
        await box.delete(7).run();
      });

      check(events).deepEquals(const [
        LazyTypedBoxEvent<String, int>(key: 7, value: Some('v')),
        LazyTypedBoxEvent<String, int>(key: 7, value: None()),
      ]);
      check(events.last.deleted).isTrue();
    });
  });

  feature('LazyKeyedBox lifecycle against real hive', () {
    scenario('close before first use never creates the box, yet is terminal', () async {
      final untouched = LazyKeyedBox<String, int>('never_used');

      await untouched.close().run();

      check(Hive.isBoxOpen('never_used')).isFalse();
      check(File('${tempDir.path}/never_used.hive').existsSync()).isFalse();
      await check(untouched.put(1, 'a').run()).throws<HiveError>();
    });

    scenario('close after use is terminal against the real box', () async {
      final box = LazyKeyedBox<String, int>('logs');
      await box.put(1, 'a').run();

      await box.close().run();

      check(Hive.isBoxOpen('logs')).isFalse();
      await check(box.get(1).run()).throws<HiveError>();
    });

    scenario('flush and compact complete; deleteFromDisk removes the box file', () async {
      final box = LazyKeyedBox<String, int>('doomed');
      await box.put(1, 'a').run();
      await box.flush().run();
      await box.compact().run();
      final boxFile = File('${tempDir.path}/doomed.hive');
      check(boxFile.existsSync()).isTrue();

      await box.deleteFromDisk().run();

      check(boxFile.existsSync()).isFalse();
    });
  });
}
