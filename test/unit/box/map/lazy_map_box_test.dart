@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/src/box/map/lazy_map_box.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  late FakeLazyBox box;
  late RecordingBoxObserver observer;
  late CountingOpener opener;
  late LazyMapBox<String, int, int> facade;

  setUp(() {
    box = FakeLazyBox(name: 'prices');
    observer = RecordingBoxObserver();
    opener = CountingOpener(box);
    facade = lazyMapBoxAround('prices', opener.open, observer: observer);
  });

  feature('LazyMapBox wiring and auto-open', () {
    scenario('construction opens nothing, and the first effect opens exactly once', () async {
      check(opener.count).equals(0);

      await facade.put(1, {'a': 1}).run();
      await facade.put(2, {'b': 2}).run();

      check(opener.count).equals(1);
      check(observer.calls.first).equals('opened:prices');
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(() => lazyMapBoxAround<String, int, DateTime>('prices', () async => box))
          .throws<AssertionError>();
    });

    scenario('an inner key that compares by identity fails the assert at the first write', () {
      final byMember = lazyMapBoxAround<Member, int, int>('prices', () async => box);

      check(() => byMember.put(1, {Member(1, 'a'): 1})).throws<AssertionError>();
    });

    scenario('a value type hive hands back untyped fails the wiring assert', () {
      check(() => lazyMapBoxAround<String, List<Person>, int>('prices', () async => box))
          .throws<AssertionError>();
      check(() => LazyMapBox<String, List<Person>, int>('nested')).throws<AssertionError>();
      check(() => lazyMapBoxAround<String, List<String>, int>('prices', () async => box))
          .returnsNormally();
    });

    scenario('the sync inspectors throw StateError before the first open, then work', () async {
      check(() => facade.length).throws<StateError>();
      check(() => facade.keys).throws<StateError>();
      check(() => facade.contains(1)).throws<StateError>();

      await facade.put(1, {'a': 1}).run();

      check(facade.length).equals(1);
      check(facade.keys).deepEquals([1]);
      check(facade.contains(1)).isTrue();
    });
  });

  feature('LazyMapBox aliasing contract', () {
    scenario('put copies: mutating the source afterwards never reaches the box', () async {
      final source = {'a': 1};

      await facade.put(1, source).run();
      source['rogue'] = 9;

      check(await facade.getOr(1).run()).deepEquals({'a': 1});
    });

    scenario('reads reject mutation, present or absent', () async {
      await facade.put(1, {'a': 1}).run();

      final present = await facade.getOr(1).run();
      final absent = await facade.getOr(9).run();

      check(() => present['rogue'] = 9).throws<UnsupportedError>();
      check(() => absent['rogue'] = 9).throws<UnsupportedError>();
    });

    scenario('update copies inward and hands back an unmodifiable view', () async {
      final mine = {'a': 1};

      await facade.update(1, (entries) => entries, ifAbsent: () => mine).run();
      mine['rogue'] = 9;

      final result = await facade.update(1, (entries) => {...entries, 'b': 2}).run();

      check(() => result['rogue'] = 9).throws<UnsupportedError>();
      check(await facade.getOr(1).run()).deepEquals({'a': 1, 'b': 2});
    });
  });

  feature('LazyMapBox reads and absent vs stored-empty', () {
    scenario('an absent key is None, a stored empty map is Some(empty)', () async {
      check((await facade.get(1).run()).isNone()).isTrue();

      await facade.put(1, <String, int>{}).run();

      check((await facade.get(1).run()).toNullable()).isNotNull().isEmpty();
    });

    scenario('values reads every stored map', () async {
      await facade.putAll({
        1: {'a': 1},
        2: {'b': 2, 'c': 3},
      }).run();

      check(await facade.values.run()).deepEquals([
        {'a': 1},
        {'b': 2, 'c': 3},
      ]);
    });
  });

  feature('LazyMapBox addAll and remove', () {
    scenario(
      'addAll gives a stored entry the incoming value where it sits, and appends the rest',
      () async {
        await facade.put(1, {'apple': 1, 'pear': 2}).run();

        await facade.addAll(1, {'plum': 3, 'apple': 9}).run();
        final mergedEntries = await facade.getOr(1).run();

        check(mergedEntries.keys).deepEquals(['apple', 'pear', 'plum']);
        check(mergedEntries).deepEquals({'apple': 9, 'pear': 2, 'plum': 3});
      },
    );

    scenario('addAll on an absent key stores a copy of the entries', () async {
      final source = {'a': 1};

      await facade.addAll(1, source).run();
      source['rogue'] = 9;

      check(await facade.getOr(1).run()).deepEquals({'a': 1});
    });

    scenario('remove takes one entry out, and the last one out leaves Some(empty)', () async {
      await facade.put(1, {'a': 1, 'b': 2, 'c': 3}).run();

      await facade.remove(1, 'b').run();
      check((await facade.getOr(1).run()).keys).deepEquals(['a', 'c']);

      await facade.remove(1, 'a').run();
      await facade.remove(1, 'c').run();
      check((await facade.get(1).run()).toNullable()).isNotNull().isEmpty();
    });

    scenario('remove is a no-op for an absent key or an absent entry', () async {
      await facade.put(1, {'a': 1}).run();
      observer.calls.clear();

      await facade.remove(9, 'a').run();
      await facade.remove(1, 'missing').run();

      check(observer.calls).isEmpty();
      check(await facade.getOr(1).run()).deepEquals({'a': 1});
    });
  });

  feature('LazyMapBox ints hive would change', () {
    const changed = ProbeKeyLimits.firstWebImpreciseInt;
    late LazyMapBox<int, int, int> byId;

    setUp(() => byId = lazyMapBoxAround('prices', opener.open));

    scenarioOutline<Task<Unit> Function()>(
      'a write holding one fails at the call',
      examples: {
        'put, as a key': () => byId.put(1, {changed: 1}),
        'put, as a value': () => byId.put(1, {1: changed}),
        'putAll, as a key': () => byId.putAll({
          1: {changed: 1},
        }),
        'putAll, as a value': () => byId.putAll({
          1: {1: changed},
        }),
      },
      outline: (write) {
        check(write).throws<ArgumentError>();
        check(opener.count).equals(0);
      },
    );

    scenarioOutline<Task<Object> Function()>(
      'an edit adding one fails when it runs, and the box is left alone',
      examples: {
        'update on a stored key': () => byId.update(1, (_) => {changed: 1}),
        'update on an absent key': () =>
            byId.update(2, (_) => {1: changed}, ifAbsent: () => {1: changed}),
        'addAll, as a key': () => byId.addAll(1, {changed: 1}),
        'addAll, as a value': () => byId.addAll(1, {1: changed}),
      },
      outline: (edit) async {
        await byId.put(1, {1: 1}).run();

        await check(edit().run()).throws<ArgumentError>();
        check(byId.keys).deepEquals([1]);
        check(await byId.getOr(1).run()).deepEquals({1: 1});
      },
    );
  });

  feature('LazyMapBox keyed surface and failure paths', () {
    scenario('putAll copies each map, and the deletes work by key', () async {
      final source = {'b': 2};

      await facade.putAll({
        1: const {'a': 1},
        2: source,
        3: const {'c': 3},
      }).run();
      source['rogue'] = 9;

      check(await facade.getOr(2).run()).deepEquals({'b': 2});

      await facade.delete(1).run();
      check(facade.keys).deepEquals([2, 3]);

      await facade.deleteAll([2]).run();
      check(facade.keys).deepEquals([3]);

      await facade.clear().run();
      check(facade.isEmpty).isTrue();
    });

    scenario('the box-key gate throws at the call site, before the box even opens', () {
      check(() => facade.put(-1, {'a': 1})).throws<ArgumentError>();

      check(opener.count).equals(0);
    });
  });

  feature('LazyMapBox watch', () {
    scenario('writes carry Some of the view, deletes carry None', () async {
      final events = await recordEvents(facade.watch(), () async {
        await facade.put(1, {'a': 1}).run();
        await facade.delete(1).run();
      });

      check(events).length.equals(2);
      check(events.first.value.toNullable()).isNotNull().deepEquals({'a': 1});
      check(() => events.first.value.toNullable()!['rogue'] = 9).throws<UnsupportedError>();
      check(events.last.value.isNone()).isTrue();
    });
  });

  feature('LazyMapBox lifecycle', () {
    scenario('close before first use never opens, yet turns the handle terminal', () async {
      await facade.close().run();

      check(opener.count).equals(0);
      check(observer.calls).deepEquals(['closed:prices']);
      await check(facade.put(1, {'a': 1}).run()).throws<HiveError>();
    });
  });
}
