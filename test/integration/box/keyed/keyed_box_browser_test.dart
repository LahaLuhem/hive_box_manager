// Browser smoke for the first public surface: the KeyedBox family's core read/write paths
// against hive_ce's IndexedDB backend, with close + reopen before every read assertion so CI
// asserts IndexedDB truth, not write-cache truth (same-browser-process stays the documented
// residual, as with the phase-0 pins).
@TestOn('browser')
@Tags(['browser'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

void main() {
  // hive_ce's web backend ignores the path (storage is IndexedDB); the argument only satisfies
  // the shared VM/web signature.
  setUpAll(() => Hive.init('hive_web_smoke'));

  feature('KeyedBox family on the browser (IndexedDB truth)', () {
    scenario('eager put / get / delete round-trips across close + reopen', () async {
      // Unique per run: IndexedDB persists across tests within one browser session.
      final boxName = 'smoke_eager_${DateTime.now().millisecondsSinceEpoch}';

      var box = await KeyedBox.open<String, int>(boxName).run();
      await box.putAll({1: 'a', 2: 'b'}).run();
      await box.close().run();

      box = await KeyedBox.open<String, int>(boxName).run();
      check(box.get(1).toNullable()).equals('a');
      check(box.length).equals(2);

      await box.delete(1).run();
      check(box.get(1).isNone()).isTrue();

      await box.deleteFromDisk().run();
    });

    scenario('lazy auto-open and TaskOption reads across close + a new instance', () async {
      final boxName = 'smoke_lazy_${DateTime.now().millisecondsSinceEpoch}';

      final first = LazyKeyedBox<String, String>(boxName);
      await first.put('k', 'v').run();
      await first.close().run();

      final second = LazyKeyedBox<String, String>(boxName);
      final present = await second.get('k').run();
      final absent = await second.get('missing').run();

      check(present.toNullable()).equals('v');
      check(absent.isNone()).isTrue();

      await second.deleteFromDisk().run();
    });
  });
}
