@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/src/box/map/map_box.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  late FakeEagerBox box;
  late RecordingBoxObserver observer;
  late MapBox<String, int, int> facade;

  setUp(() {
    box = FakeEagerBox(name: 'prices');
    observer = RecordingBoxObserver();
    facade = mapBoxAround(box, observer: observer);
  });

  feature('MapBox wiring', () {
    scenario('a custom codec owns the raw encoding and the decode round-trip', () async {
      final date = DateTime.utc(2026, 7, 21);
      final dateKeyed = mapBoxAround<String, int, DateTime>(box, codec: const DateKeyCodec());

      await dateKeyed.put(date, {'a': 1}).run();

      check(box.store.keys).deepEquals([date.toIso8601String()]);
      check(dateKeyed.keys).deepEquals([date]);
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(() => mapBoxAround<String, int, DateTime>(box)).throws<AssertionError>();
    });

    scenario('an inner key type a restart breaks fails the wiring assert, at the call', () {
      check(() => mapBoxAround<Person, int, int>(box)).throws<AssertionError>();
      check(() => MapBox.open<Person, int, int>('by_person')).throws<AssertionError>();
      check(() => mapBoxAround<Colour, int, int>(box)).returnsNormally();
    });

    scenario('a value type hive hands back untyped fails the wiring assert, at the call', () {
      check(() => mapBoxAround<String, List<Person>, int>(box)).throws<AssertionError>();
      check(() => MapBox.open<String, List<Person>, int>('nested')).throws<AssertionError>();
      check(() => mapBoxAround<String, List<String>, int>(box)).returnsNormally();
    });
  });

  feature('MapBox aliasing contract', () {
    scenario('put copies: mutating the source afterwards never reaches the box', () async {
      final source = {'a': 1};

      await facade.put(1, source).run();
      source['rogue'] = 9;

      check(facade.getOr(1)).deepEquals({'a': 1});
    });

    scenario('returned maps reject mutation, present or absent', () async {
      await facade.put(1, {'a': 1}).run();

      check(() => facade.getOr(1)['rogue'] = 9).throws<UnsupportedError>();
      check(() => facade.getOr(9)['rogue'] = 9).throws<UnsupportedError>();
    });

    scenario('update copies inward and hands back an unmodifiable view', () async {
      final mine = {'a': 1};

      await facade.update(1, (entries) => entries, ifAbsent: () => mine).run();
      mine['rogue'] = 9;

      check(facade.getOr(1)).deepEquals({'a': 1});

      final result = await facade.update(1, (entries) => {...entries, 'b': 2}).run();

      check(() => result['rogue'] = 9).throws<UnsupportedError>();
      check(facade.getOr(1)).deepEquals({'a': 1, 'b': 2});
    });

    scenario('watch payloads carry the same unmodifiable views', () async {
      final events = await recordEvents(facade.watch(), () => facade.put(1, {'a': 1}).run());

      check(events).length.equals(1);
      check(events.first.value).deepEquals({'a': 1});
      check(() => events.first.value['rogue'] = 9).throws<UnsupportedError>();
    });
  });

  feature('MapBox absent vs stored-empty', () {
    scenario('an absent key is None, a stored empty map is Some(empty)', () async {
      check(facade.get(1).isNone()).isTrue();

      await facade.put(1, <String, int>{}).run();

      check(facade.get(1).toNullable()).isNotNull().isEmpty();
      check(facade.contains(1)).isTrue();
    });
  });

  feature('MapBox addAll and remove', () {
    scenario(
      'addAll gives a stored entry the incoming value where it sits, and appends the rest',
      () async {
        await facade.put(1, {'apple': 1, 'pear': 2}).run();

        await facade.addAll(1, {'plum': 3, 'apple': 9}).run();

        check(facade.getOr(1).keys).deepEquals(['apple', 'pear', 'plum']);
        check(facade.getOr(1)).deepEquals({'apple': 9, 'pear': 2, 'plum': 3});
      },
    );

    scenario('addAll on an absent key stores a copy of the entries', () async {
      final source = {'a': 1};

      await facade.addAll(1, source).run();
      source['rogue'] = 9;

      check(facade.getOr(1)).deepEquals({'a': 1});
    });

    scenario('remove takes one entry out and keeps the rest in order', () async {
      await facade.put(1, {'a': 1, 'b': 2, 'c': 3}).run();

      await facade.remove(1, 'b').run();

      check(facade.getOr(1).keys).deepEquals(['a', 'c']);
    });

    scenario('removing the last entry leaves Some(empty), never a deleted key', () async {
      await facade.put(1, {'a': 1}).run();

      await facade.remove(1, 'a').run();

      check(facade.get(1).toNullable()).isNotNull().isEmpty();
      check(facade.contains(1)).isTrue();
    });

    scenario('remove is a no-op for an absent key or an absent entry', () async {
      await facade.put(1, {'a': 1}).run();
      observer.calls.clear();

      await facade.remove(9, 'a').run();
      await facade.remove(1, 'missing').run();

      check(observer.calls).isEmpty();
      check(facade.getOr(1)).deepEquals({'a': 1});
    });
  });

  feature("MapBox inner int keys hive can't store exactly", () {
    final imprecise = {ProbeKeyLimits.firstWebImpreciseInt: 'a'};
    late MapBox<int, String, int> byId;

    setUp(() => byId = mapBoxAround(box));

    scenarioOutline<Task<Unit> Function()>(
      'a write with one fails at the call',
      examples: {
        'put': () => byId.put(1, imprecise),
        'putAll': () => byId.putAll({1: imprecise}),
        'addAll': () => byId.addAll(1, imprecise),
      },
      outline: (write) => check(write).throws<ArgumentError>(),
    );

    scenarioOutline<int>(
      "update can't store one either: the task fails and the box is left alone",
      examples: {'on a stored key': 1, 'on an absent key': 2},
      outline: (key) async {
        await byId.put(1, {1: 'stored'}).run();

        await check(byId.update(key, (_) => imprecise, ifAbsent: () => imprecise).run())
            .throws<ArgumentError>();

        check(byId.keys).deepEquals([1]);
        check(byId.getOr(1)).deepEquals({1: 'stored'});
      },
    );
  });

  feature('MapBox keyed surface and failure paths', () {
    scenario('putAll copies each map, and the inspectors and deletes work by key', () async {
      final source = {'b': 2};

      await facade.putAll({
        1: const {'a': 1},
        2: source,
        3: const {'c': 3},
      }).run();
      source['rogue'] = 9;

      check(facade.values).deepEquals([
        {'a': 1},
        {'b': 2},
        {'c': 3},
      ]);
      check(facade.length).equals(3);

      await facade.delete(1).run();
      check(facade.keys).deepEquals([2, 3]);

      await facade.deleteAll([2]).run();
      check(facade.keys).deepEquals([3]);

      await facade.clear().run();
      check(facade.isEmpty).isTrue();
    });

    scenario('the box-key gate throws at the call site and nothing is written', () {
      check(() => facade.put(-1, {'a': 1})).throws<ArgumentError>();
      check(
        () => facade.putAll({
          -1: const {'a': 1},
        }),
      ).throws<ArgumentError>();

      check(box.store).isEmpty();
    });

    scenario('close is terminal: sync reads and later effects surface hive errors', () async {
      await facade.put(1, {'a': 1}).run();

      await facade.close().run();

      check(() => facade.get(1)).throws<HiveError>();
      await check(facade.addAll(1, {'b': 2}).run()).throws<HiveError>();
    });
  });
}
