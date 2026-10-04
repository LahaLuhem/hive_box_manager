@TestOn('browser')
@Tags(['browser'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  const ada = Person('ada', 36);
  const olderAda = Person('ada', 37);
  const bob = Person('bob', 40);

  setUpAll(() {
    // hive_ce's web backend ignores the path, since storage is IndexedDB.
    Hive
      ..init('hive_web_maps')
      ..registerAdapter(const PersonAdapter());
  });

  feature('Map boxes on the browser (IndexedDB truth)', () {
    scenario('eager maps come back typed after a reopen, and addAll merges into them', () async {
      final boxName = uniqueBoxName('maps_eager');
      Future<MapBox<String, Person, int>> open() => MapBox.open<String, Person, int>(boxName).run();

      var box = await open();
      await box.put(1, {'ada': ada, 'bob': bob}).run();
      await box.close().run();

      box = await open();

      check(box.getOr(1)).isA<Map<String, Person>>();

      await box.addAll(1, {'ada': olderAda}).run();

      check(box.getOr(1).keys).deepEquals(['ada', 'bob']);
      check(box.getOr(1)['ada']).equals(olderAda);

      await box.deleteFromDisk().run();
    });

    scenario('lazy maps come back typed in a new instance, in order', () async {
      final boxName = uniqueBoxName('maps_lazy');

      final first = LazyMapBox<String, Person, int>(boxName);
      await first.put(1, {'bob': bob, 'ada': ada}).run();
      await first.close().run();

      final second = LazyMapBox<String, Person, int>(boxName);
      final read = await second.getOr(1).run();

      check(read).isA<Map<String, Person>>();
      check(read.keys).deepEquals(['bob', 'ada']);

      await second.deleteFromDisk().run();
    });
  });
}
