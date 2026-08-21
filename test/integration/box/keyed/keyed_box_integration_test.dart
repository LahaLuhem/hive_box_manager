// The eager façade end to end against real hive_ce on temp dirs, through the public barrel:
// per-method round-trips, disk truth across close + reopen, cipher and custom-codec
// pass-through, the call-site corruption gate, and the terminal lifecycle.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/codecs/date_key_codec.dart';
import '../../../support/doubles/recording_box_observer.dart';
import '../../../support/pins/probe_key_limits.dart';

/// AES-256 wants exactly this many key bytes.
const aesKeyBytes = 32;

/// Collects the events [stream] emits while [act] runs, draining the event queue before
/// returning so no in-flight notification is missed.
Future<List<TypedBoxEvent<String, int>>> record(
  Stream<TypedBoxEvent<String, int>> stream,
  Future<void> Function() act,
) async {
  final events = <TypedBoxEvent<String, int>>[];
  final subscription = stream.listen(events.add);
  await act();
  await pumpEventQueue();
  await subscription.cancel();

  return events;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_keyed_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('KeyedBox acquisition against real hive', () {
    scenario('open is a lazy Task and dispatches onOpened when run', () async {
      final observer = RecordingBoxObserver();
      final openTask = KeyedBox.open<String, int>('users', observer: observer);

      check(observer.calls).isEmpty();

      final box = await openTask.run();

      check(box.name).equals('users');
      check(observer.calls).deepEquals(['opened:users']);
    });

    scenario('reopening a different kind under the same name surfaces hive error', () async {
      final eager = await KeyedBox.open<String, int>('users').run();
      await eager.put(1, 'a').run();

      final wrongKind = LazyKeyedBox<String, int>('users');

      await check(wrongKind.ensureInitialised().run()).throws<HiveError>();
    });
  });

  feature('KeyedBox CRUD against real hive', () {
    scenario('every read and write member round-trips', () async {
      final box = await KeyedBox.open<String, int>('users').run();

      await box.put(1, 'a').run();
      await box.putAll({2: 'b', 3: 'c'}).run();

      check(box.get(1).toNullable()).equals('a');
      check(box.get(9).isNone()).isTrue();
      check(box.getOr(9, 'fallback')).equals('fallback');
      check(box.contains(2)).isTrue();
      check(box.values).deepEquals(['a', 'b', 'c']);
      check(box.keys).deepEquals([1, 2, 3]);
      check(box.length).equals(3);
      check(box.isNotEmpty).isTrue();

      check(await box.update(1, (value) => '$value!').run()).equals('a!');
      check(await box.update(9, (value) => value, ifAbsent: () => 'seed').run()).equals('seed');
      await check(box.update(8, (value) => value).run()).throws<ArgumentError>();

      await box.delete(1).run();
      await box.deleteAll([2, 3]).run();
      await box.clear().run();

      check(box.isEmpty).isTrue();
    });

    scenario('values persist across close and reopen (disk truth)', () async {
      var box = await KeyedBox.open<String, int>('users').run();
      await box.put(7, 'persisted').run();
      await box.close().run();

      box = await KeyedBox.open<String, int>('users').run();

      check(box.get(7).toNullable()).equals('persisted');
    });

    scenario('a custom key codec owns the raw domain round-trip', () async {
      final date = DateTime.utc(2026, 7, 21);
      final box = await KeyedBox.open<String, DateTime>('dated', codec: const DateKeyCodec()).run();

      await box.put(date, 'v').run();

      check(box.keys).deepEquals([date]);
      check(box.get(date).toNullable()).equals('v');
    });

    scenario('an encrypted box reads back with the same cipher', () async {
      final cipher = HiveAesCipher(List.filled(aesKeyBytes, 7));
      var box = await KeyedBox.open<String, int>('secret', cipher: cipher).run();
      await box.put(1, 'ciphered').run();
      await box.close().run();

      box = await KeyedBox.open<String, int>('secret', cipher: cipher).run();

      check(box.get(1).toNullable()).equals('ciphered');
    });

    scenario('the corruption gate rejects what release-mode hive corrupts on', () async {
      final box = await KeyedBox.open<String, int>('users').run();

      check(() => box.put(-1, 'v')).throws<ArgumentError>();
      check(() => box.put(HiveKeyLimits.maxIntKey + 1, 'v')).throws<ArgumentError>();

      check(box.isEmpty).isTrue();
    });
  });

  feature('KeyedBox watch against real hive', () {
    scenario('events arrive typed and deletes carry the just-deleted value', () async {
      final box = await KeyedBox.open<String, int>('users').run();

      final events = await record(box.watch(), () async {
        await box.put(7, 'v').run();
        await box.delete(7).run();
      });

      check(events).deepEquals(const [
        TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: false),
        TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: true),
      ]);
    });

    scenario('a key filter narrows the stream to that key', () async {
      final box = await KeyedBox.open<String, int>('users').run();

      final events = await record(box.watch(key: 2), () async {
        await box.putAll({1: 'a', 2: 'b'}).run();
      });

      check(events)
          .deepEquals(const [TypedBoxEvent<String, int>(key: 2, value: 'b', deleted: false)]);
    });
  });

  feature('KeyedBox lifecycle against real hive', () {
    scenario('flush lands pending writes in the box file', () async {
      final box = await KeyedBox.open<String, int>('users').run();
      await box.put(1, 'a').run();

      await box.flush().run();

      check(File('${tempDir.path}/users.hive').existsSync()).isTrue();
    });

    scenario('compact completes and the box stays readable', () async {
      final box = await KeyedBox.open<String, int>('users').run();
      await box.putAll({1: 'a', 2: 'b'}).run();
      await box.delete(1).run();

      await box.compact().run();

      check(box.get(2).toNullable()).equals('b');
    });

    scenario('close is terminal: sync reads and later effects surface hive errors', () async {
      final box = await KeyedBox.open<String, int>('users').run();
      await box.put(1, 'a').run();

      await box.close().run();

      check(() => box.get(1)).throws<HiveError>();
      await check(box.put(2, 'b').run()).throws<HiveError>();
    });

    scenario('deleteFromDisk removes the box file', () async {
      final box = await KeyedBox.open<String, int>('doomed').run();
      await box.put(1, 'a').run();
      await box.flush().run();
      final boxFile = File('${tempDir.path}/doomed.hive');
      check(boxFile.existsSync()).isTrue();

      await box.deleteFromDisk().run();

      check(boxFile.existsSync()).isFalse();
    });
  });
}
