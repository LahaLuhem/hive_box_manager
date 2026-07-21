// The eager single-value façade end to end against real hive_ce on temp dirs, through the
// public barrel: the slot-0 disk-truth compatibility pin, per-member round-trips, the Option
// watch stream, cipher pass-through, and the terminal lifecycle.
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

/// AES-256 wants exactly this many key bytes.
const aesKeyBytes = 32;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_single_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('SingleValueBox slot compatibility against real hive', () {
    scenario('the value lands under raw key 0, where 0.0.x single boxes kept it', () async {
      final facade = await SingleValueBox.open<String>('config').run();
      await facade.set('v').run();
      await facade.close().run();

      final rawBox = await Hive.openBox<Object?>('config');

      check(rawBox.get(0)).equals('v');
      check(rawBox.length).equals(1);
    });

    scenario('a value written raw under key 0 reads through the façade in place', () async {
      final rawBox = await Hive.openBox<Object?>('config');
      await rawBox.put(0, 'legacy');
      await rawBox.close();

      final facade = await SingleValueBox.open<String>('config').run();

      check(facade.get().toNullable()).equals('legacy');
    });
  });

  feature('SingleValueBox CRUD against real hive', () {
    scenario('set, get, getOr, update, and clear round-trip', () async {
      final facade = await SingleValueBox.open<String>('config').run();

      check(facade.get().isNone()).isTrue();
      check(facade.getOr('fallback')).equals('fallback');
      check(facade.isEmpty).isTrue();

      await facade.set('v').run();

      check(facade.get().toNullable()).equals('v');
      check(facade.length).equals(1);

      check(await facade.update((value) => '$value!').run()).equals('v!');

      await facade.clear().run();

      check(facade.get().isNone()).isTrue();
      await check(facade.update((value) => value).run()).throws<ArgumentError>();
      check(await facade.update((value) => value, ifAbsent: () => 'seed').run()).equals('seed');
    });

    scenario('the value persists across close and reopen (disk truth)', () async {
      var facade = await SingleValueBox.open<String>('config').run();
      await facade.set('persisted').run();
      await facade.close().run();

      facade = await SingleValueBox.open<String>('config').run();

      check(facade.get().toNullable()).equals('persisted');
    });

    scenario('an encrypted box reads back with the same cipher', () async {
      final cipher = HiveAesCipher(List.filled(aesKeyBytes, 7));
      var facade = await SingleValueBox.open<String>('secret', cipher: cipher).run();
      await facade.set('ciphered').run();
      await facade.close().run();

      facade = await SingleValueBox.open<String>('secret', cipher: cipher).run();

      check(facade.get().toNullable()).equals('ciphered');
    });
  });

  feature('SingleValueBox watch against real hive', () {
    scenario('sets stream Some, clears stream None', () async {
      final facade = await SingleValueBox.open<String>('config').run();
      final events = <Option<String>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.set('v').run();
      await facade.clear().run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [Some('v'), None()]);
    });
  });

  feature('SingleValueBox lifecycle against real hive', () {
    scenario('close is terminal; deleteFromDisk removes the box file', () async {
      final facade = await SingleValueBox.open<String>('doomed').run();
      await facade.set('v').run();
      await facade.flush().run();
      final boxFile = File('${tempDir.path}/doomed.hive');
      check(boxFile.existsSync()).isTrue();

      await facade.deleteFromDisk().run();

      check(boxFile.existsSync()).isFalse();
      check(facade.get).throws<HiveError>();
    });
  });
}
