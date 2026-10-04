// The eager single-value façade end to end, against real hive_ce on a temp dir and through the public
// barrel. Includes the slot-0 compatibility pin.
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  final tempHive = useTempHive('hbm_single_');

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

    scenario("an encrypted box reads back with its cipher and won't open without it", () async {
      final cipher = testCipher();
      var facade = await SingleValueBox.open<String>('secret', cipher: cipher).run();
      await facade.set('ciphered').run();
      await facade.close().run();

      facade = await SingleValueBox.open<String>('secret', cipher: cipher).run();

      check(facade.get().toNullable()).equals('ciphered');
      await facade.close().run();
      await check(SingleValueBox.open<String>('secret').run()).throws<HiveError>();
    });
  });

  feature('SingleValueBox watch against real hive', () {
    scenario('sets stream Some, clears stream None', () async {
      final facade = await SingleValueBox.open<String>('config').run();
      final events = await recordEvents(facade.watch(), () async {
        await facade.set('v').run();
        await facade.clear().run();
      });

      check(events).deepEquals(const [Some('v'), None()]);
    });
  });

  feature('SingleValueBox lifecycle against real hive', () {
    scenario('close is terminal; deleteFromDisk removes the box file', () async {
      final facade = await SingleValueBox.open<String>('doomed').run();
      await facade.set('v').run();
      await facade.flush().run();
      final boxFile = tempHive.boxFile('doomed');
      check(boxFile.existsSync()).isTrue();

      await facade.deleteFromDisk().run();

      check(boxFile.existsSync()).isFalse();
      check(facade.get).throws<HiveError>();
    });
  });
}
