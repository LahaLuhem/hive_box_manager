@TestOn('browser')
@Tags(['browser'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/fixtures/member.dart';

void main() {
  setUpAll(() {
    // hive_ce's web backend ignores the path, since storage is IndexedDB.
    Hive.init('hive_web_sets');
    if (!Hive.isAdapterRegistered(MemberAdapter().typeId)) Hive.registerAdapter(MemberAdapter());
  });

  feature('Set boxes on the browser (IndexedDB truth)', () {
    scenario('eager sets come back typed after a reopen, and add keeps the stored id', () async {
      // Unique per run: IndexedDB persists across tests within one browser session.
      final boxName = 'sets_eager_${DateTime.now().millisecondsSinceEpoch}';
      Future<SetBox<Member, int>> open() =>
          SetBox.open<Member, int>(boxName, idOf: (member) => member.id).run();

      var box = await open();
      await box.put(1, [Member(1, 'a'), Member(2, 'b')]).run();
      await box.close().run();

      box = await open();
      await box.add(1, Member(1, 'again')).run();

      check(box.getOr(1)).isA<Set<Member>>();
      check(box.getOr(1).map((member) => member.name)).deepEquals(['a', 'b']);

      await box.deleteFromDisk().run();
    });

    scenario('lazy sets come back typed in a new instance', () async {
      final boxName = 'sets_lazy_${DateTime.now().millisecondsSinceEpoch}';

      final first = LazySetBox<String, int>(boxName);
      await first.put(1, ['b', 'a', 'b']).run();
      await first.close().run();

      final second = LazySetBox<String, int>(boxName);
      final read = await second.getOr(1).run();

      check(read).isA<Set<String>>();
      check(read.toList()).deepEquals(['b', 'a']);

      await second.deleteFromDisk().run();
    });
  });
}
