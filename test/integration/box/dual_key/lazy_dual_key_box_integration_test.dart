// Exercises the lazy dual-key façade end to end against real hive_ce on temp dirs, through the
// public barrel. Covered here: auto-opening reverse queries answering from disk truth, both of
// the shipped codecs persisting across a fresh instance, the Option-valued watch payloads, and
// the no-op rider for closing a never-used handle.
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
    tempDir = Directory.systemTemp.createTempSync('hbm_lazy_dual_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('LazyDualKeyBox against real hive', () {
    scenario('construction touches nothing; queries auto-open the real box', () async {
      final facade = LazyDualKeyBox<String, int, int>('grid');

      check(Hive.isBoxOpen('grid')).isFalse();

      final matches = await facade.queryByPrimary(1).run();

      check(Hive.isBoxOpen('grid')).isTrue();
      check(matches).isEmpty();
    });

    scenario('the composite default persists across close and a new instance', () async {
      final first = LazyDualKeyBox<String, int, int>('grid');
      await first.put(-7, 9, 'persisted').run();
      await first.close().run();

      final second = LazyDualKeyBox<String, int, int>('grid');

      check((await second.get(-7, 9).run()).toNullable()).equals('persisted');
      check(second.keys).deepEquals([(-7, 9)]);
    });

    scenario('the packed opt-in reads a raw bit-shifted legacy box natively', () async {
      final legacyBox = await Hive.openLazyBox<Object?>('legacy');
      await legacyBox.put((7 << 16) | 9, 'legacy value');
      await legacyBox.close();

      final facade = LazyDualKeyBox<String, int, int>('legacy', codec: const PackedIntDualCodec());

      check(await facade.queryBySecondary(9).run()).deepEquals(['legacy value']);
      check((await facade.get(7, 9).run()).toNullable()).equals('legacy value');
    });

    scenario('queries collect every match by the requested part on disk', () async {
      final facade = LazyDualKeyBox<String, int, int>('grid');
      await facade.putAll({(1, 1): 'a', (1, 2): 'b', (2, 1): 'c'}).run();

      check(await facade.queryByPrimary(1).run()).deepEquals(['a', 'b']);
      check(await facade.queryBySecondary(1).run()).deepEquals(['a', 'c']);

      await facade.delete(1, 1).run();

      check(await facade.queryByPrimary(1).run()).deepEquals(['b']);
    });

    scenario('writes carry Some with record keys, deletes carry None', () async {
      final facade = LazyDualKeyBox<String, int, int>('grid');
      await facade.ensureInitialised().run();
      final events = <LazyTypedBoxEvent<String, (int, int)>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(1, 2, 'v').run();
      await facade.delete(1, 2).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [
        LazyTypedBoxEvent<String, (int, int)>(key: (1, 2), value: Some('v')),
        LazyTypedBoxEvent<String, (int, int)>(key: (1, 2), value: None()),
      ]);
    });

    scenario('close before first use never creates the box, yet is terminal', () async {
      final untouched = LazyDualKeyBox<String, int, int>('never_used');

      await untouched.close().run();

      check(Hive.isBoxOpen('never_used')).isFalse();
      check(File('${tempDir.path}/never_used.hive').existsSync()).isFalse();
      await check(untouched.put(1, 2, 'v').run()).throws<HiveError>();
    });
  });
}
