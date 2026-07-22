// The lazy single-value façade end to end against real hive_ce on temp dirs, through the public
// barrel: auto-open, the slot-0 disk truth via a new instance, the Option watch stream on the
// lazy axis, and the pre-first-use close no-op (never creates the box).
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_lazy_single_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('LazySingleValueBox against real hive', () {
    scenario('construction touches nothing; the first effect opens and hits slot 0', () async {
      final facade = LazySingleValueBox<String>('config');

      check(Hive.isBoxOpen('config')).isFalse();

      await facade.set('v').run();

      check(Hive.isBoxOpen('config')).isTrue();
      final read = await facade.get().run();
      check(read.toNullable()).equals('v');
    });

    scenario('reads are TaskOption-shaped and getOr falls back', () async {
      final facade = LazySingleValueBox<String>('config');

      final absent = await facade.get().run();
      check(absent.isNone()).isTrue();
      check(await facade.getOr('fallback').run()).equals('fallback');

      await facade.set('v').run();

      check(await facade.getOr('fallback').run()).equals('v');
      check(facade.length).equals(1);
    });

    scenario('update mirrors Map.update; clear unsets', () async {
      final facade = LazySingleValueBox<String>('config');

      await check(facade.update((value) => value).run()).throws<ArgumentError>();
      check(await facade.update((value) => value, ifAbsent: () => 'seed').run()).equals('seed');
      check(await facade.update((value) => '$value!').run()).equals('seed!');

      await facade.clear().run();

      final unset = await facade.get().run();
      check(unset.isNone()).isTrue();
    });

    scenario('the value persists across close and a new instance (disk truth)', () async {
      final first = LazySingleValueBox<String>('config');
      await first.set('persisted').run();
      await first.close().run();

      final second = LazySingleValueBox<String>('config');

      check((await second.get().run()).toNullable()).equals('persisted');
    });

    scenario('sets stream Some, clears stream None', () async {
      final facade = LazySingleValueBox<String>('config');
      await facade.ensureInitialised().run();
      final events = <Option<String>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.set('v').run();
      await facade.clear().run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [Some('v'), None()]);
    });

    scenario('close before first use never creates the box, yet is terminal', () async {
      final untouched = LazySingleValueBox<String>('never_used');

      await untouched.close().run();

      check(Hive.isBoxOpen('never_used')).isFalse();
      check(File('${tempDir.path}/never_used.hive').existsSync()).isFalse();
      await check(untouched.set('v').run()).throws<HiveError>();
    });
  });
}
