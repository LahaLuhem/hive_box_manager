// Real hive, since the race needs its async disk reads.
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:test/test.dart';

import '../support/support.dart';

int increment(int count) => count + 1;

void main() {
  useTempHive('hbm_concurrent_');

  feature('concurrent writes to one key of a lazy box', () {
    scenarioOutline<({Future<Iterable<Object?>> Function() race, List<Object?> landed})>(
      '2 read-modify-writes started together both land',
      examples: {
        'LazyKeyedBox.update': (
          race: () async {
            final box = LazyKeyedBox<int, String>('race');
            await box.put('n', 0).run();
            await [box.update('n', increment).run(), box.update('n', increment).run()].wait;

            return [(await box.get('n').run()).toNullable()];
          },
          landed: [2],
        ),
        'LazySingleValueBox.update': (
          race: () async {
            final box = LazySingleValueBox<int>('race');
            await box.set(0).run();
            await [box.update(increment).run(), box.update(increment).run()].wait;

            return [(await box.get().run()).toNullable()];
          },
          landed: [2],
        ),
        'LazyDualKeyBox.update': (
          race: () async {
            final box = LazyDualKeyBox<int, int, int>('race');
            await box.put(1, 2, 0).run();
            await [box.update(1, 2, increment).run(), box.update(1, 2, increment).run()].wait;

            return [(await box.get(1, 2).run()).toNullable()];
          },
          landed: [2],
        ),
        'LazyListBox.add': (
          race: () async {
            final box = LazyListBox<String, int>('race');
            await box.put(1, ['a']).run();
            await [box.add(1, 'x').run(), box.add(1, 'y').run()].wait;

            return await box.getOr(1).run();
          },
          landed: ['a', 'x', 'y'],
        ),
        'LazySetBox.add': (
          race: () async {
            final box = LazySetBox<String, int>('race');
            await box.put(1, ['a']).run();
            await [box.add(1, 'x').run(), box.add(1, 'y').run()].wait;

            return await box.getOr(1).run();
          },
          landed: ['a', 'x', 'y'],
        ),
        'LazyMapBox.addAll': (
          race: () async {
            final box = LazyMapBox<String, int, int>('race');
            await box.put(1, {'a': 0}).run();
            await [
              box.addAll(1, {'x': 1}).run(),
              box.addAll(1, {'y': 2}).run(),
            ].wait;

            return (await box.getOr(1).run()).keys;
          },
          landed: ['a', 'x', 'y'],
        ),
        'LazyMapBox.remove': (
          race: () async {
            final box = LazyMapBox<String, int, int>('race');
            await box.put(1, {'a': 1, 'b': 2}).run();
            await [box.remove(1, 'a').run(), box.remove(1, 'b').run()].wait;

            return (await box.getOr(1).run()).keys;
          },
          landed: [],
        ),
      },
      outline: (example) async => check(await example.race()).deepEquals(example.landed),
    );

    scenario('updates through 2 handles on one box name both land', () async {
      final ui = LazyKeyedBox<int, String>('shared');
      final sync = LazyKeyedBox<int, String>('shared');
      await ui.put('n', 0).run();

      await [ui.update('n', increment).run(), sync.update('n', increment).run()].wait;

      check((await sync.get('n').run()).toNullable()).equals(2);
    });
  });
}
