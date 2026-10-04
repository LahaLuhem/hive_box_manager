@TestOn('vm')
@Tags(['integration'])
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
  const cy = Person('cy', 20);
  useTempHive('hbm_lazy_map_box_');

  setUpAll(() => Hive.registerAdapter(const PersonAdapter()));

  LazyMapBox<String, Person, int> people() => LazyMapBox<String, Person, int>('people');

  feature('LazyMapBox against real hive', () {
    scenario('a map of a custom value type reads back typed in a new instance', () async {
      final first = people();
      await first.put(1, {'ada': ada, 'bob': bob}).run();
      await first.close().run();

      final read = await people().getOr(1).run();

      check(read).isA<Map<String, Person>>();
      check(read).deepEquals({'ada': ada, 'bob': bob});
      check(() => read['rogue'] = bob).throws<UnsupportedError>();
    });

    scenario('construction touches nothing, and inspectors work after the first effect', () async {
      final box = people();

      check(Hive.isBoxOpen('people')).isFalse();
      check(() => box.length).throws<StateError>();

      await box.put(1, {'ada': ada}).run();

      check(Hive.isBoxOpen('people')).isTrue();
      check(box.keys).deepEquals([1]);
    });

    scenario('addAll and remove in a new instance work on the map read from disk', () async {
      final first = people();
      await first.put(1, {'ada': ada, 'bob': bob}).run();
      await first.close().run();

      final second = people();
      await second.addAll(1, {'ada': olderAda, 'cy': cy}).run();
      await second.remove(1, 'bob').run();
      final read = await second.getOr(1).run();

      check(read.keys).deepEquals(['ada', 'cy']);
      check(read['ada']).equals(olderAda);
    });

    scenario('insertion order survives, and absent stays apart from stored-empty', () async {
      final first = people();
      await first.putAll({
        1: {'cy': cy, 'ada': ada, 'bob': bob},
        2: const {},
      }).run();
      await first.close().run();

      final second = people();

      check((await second.getOr(1).run()).keys).deepEquals(['cy', 'ada', 'bob']);
      check((await second.get(2).run()).toNullable()).isNotNull().isEmpty();
      check((await second.get(9).run()).isNone()).isTrue();
    });
  });
}
