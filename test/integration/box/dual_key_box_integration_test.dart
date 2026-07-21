// The eager dual-key façade end to end against real hive_ce on temp dirs, through the public
// barrel: both shipped codecs on disk, the 0.0.x bit-shift data-compatibility pin (raw
// bit-shifted keys read natively through the packed codec), reverse queries incl. the
// 10K-entry scan sanity, and the terminal lifecycle.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

/// The 10K scan-sanity grid: primaries × secondaries entries, one query per axis.
const scanGridSide = 100;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_dual_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('DualKeyBox codecs against real hive', () {
    scenario('the composite default round-trips and persists across reopen', () async {
      var facade = await DualKeyBox.open<String, int, int>('grid').run();
      await facade.put(-7, 9, 'negative parts are fine').run();
      await facade.close().run();

      facade = await DualKeyBox.open<String, int, int>('grid').run();

      check(facade.get(-7, 9).toNullable()).equals('negative parts are fine');
      check(facade.keys).deepEquals([(-7, 9)]);
    });

    scenario('the packed opt-in round-trips and persists across reopen', () async {
      var facade = await DualKeyBox.open<String, int, int>(
        'packed',
        codec: const PackedIntDualCodec(),
      ).run();
      await facade.put(7, 9, 'packed').run();
      await facade.close().run();

      facade = await DualKeyBox.open<String, int, int>(
        'packed',
        codec: const PackedIntDualCodec(),
      ).run();

      check(facade.get(7, 9).toNullable()).equals('packed');
    });

    scenario('0.0.x bit-shifted keys read natively through the packed codec', () async {
      // A legacy box written raw with the 0.0.x `.bitShift` scheme: (p << 16) | s.
      final legacyBox = await Hive.openBox<Object?>('legacy');
      await legacyBox.put((7 << 16) | 9, 'legacy value');
      await legacyBox.close();

      final facade = await DualKeyBox.open<String, int, int>(
        'legacy',
        codec: const PackedIntDualCodec(),
      ).run();

      check(facade.get(7, 9).toNullable()).equals('legacy value');
      check(facade.keys).deepEquals([(7, 9)]);
      check(facade.queryByPrimary(7)).deepEquals(['legacy value']);
    });
  });

  feature('DualKeyBox queries against real hive', () {
    scenario('no matches is a plain empty list, and absent-vs-empty stays honest', () async {
      final facade = await DualKeyBox.open<String, int, int>('grid').run();

      check(facade.queryByPrimary(42)).isEmpty();
      check(facade.get(42, 1).isNone()).isTrue();
    });

    scenario('a 10K-entry scan answers both axes exactly (the O(K) sanity)', () async {
      final facade = await DualKeyBox.open<String, int, int>('grid').run();
      await facade.putAll({
        for (var primary = 0; primary < scanGridSide; primary++)
          for (var secondary = 0; secondary < scanGridSide; secondary++)
            (primary, secondary): '$primary/$secondary',
      }).run();

      check(facade.length).equals(scanGridSide * scanGridSide);

      final byPrimary = facade.queryByPrimary(42);
      check(byPrimary).length.equals(scanGridSide);
      check(byPrimary.every((value) => value.startsWith('42/'))).isTrue();

      final bySecondary = facade.queryBySecondary(7);
      check(bySecondary).length.equals(scanGridSide);
      check(bySecondary.every((value) => value.endsWith('/7'))).isTrue();
    });
  });

  feature('DualKeyBox lifecycle against real hive', () {
    scenario('update mirrors Map.update; deletes shrink queries; close is terminal', () async {
      final facade = await DualKeyBox.open<String, int, int>('grid').run();
      await facade.putAll({(1, 1): 'a', (1, 2): 'b'}).run();

      check(await facade.update(1, 1, (value) => '$value!').run()).equals('a!');
      await check(facade.update(9, 9, (value) => value).run()).throws<ArgumentError>();

      await facade.delete(1, 1).run();
      check(facade.queryByPrimary(1)).deepEquals(['b']);

      await facade.close().run();
      check(() => facade.get(1, 2)).throws<HiveError>();
    });

    scenario('deleteFromDisk removes the box file', () async {
      final facade = await DualKeyBox.open<String, int, int>('doomed').run();
      await facade.put(1, 1, 'v').run();
      await facade.flush().run();
      final boxFile = File('${tempDir.path}/doomed.hive');
      check(boxFile.existsSync()).isTrue();

      await facade.deleteFromDisk().run();

      check(boxFile.existsSync()).isFalse();
    });
  });
}
