@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/set/lazy_set_box.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  late FakeLazyBox box;
  late RecordingBoxObserver observer;
  late CountingOpener opener;
  late LazySetBox<String, int> facade;
  late LazySetBox<Member, int> members;
  late FakeLazyBox memberBox;

  setUp(() {
    box = FakeLazyBox(name: 'tags');
    observer = RecordingBoxObserver();
    opener = CountingOpener(box);
    facade = lazySetBoxAround('tags', opener.open, observer: observer);
    memberBox = FakeLazyBox(name: 'members');
    members = lazySetBoxAround('members', () async => memberBox, idOf: (member) => member.id);
  });

  feature('LazySetBox wiring and auto-open', () {
    scenario('construction opens nothing, and the first effect opens exactly once', () async {
      check(opener.count).equals(0);

      await facade.put(1, ['a']).run();
      await facade.put(2, ['b']).run();

      check(opener.count).equals(1);
      check(observer.calls.first).equals('opened:tags');
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(() => lazySetBoxAround<String, DateTime>('tags', () async => box))
          .throws<AssertionError>();
    });

    scenario('a custom element type without idOf fails the wiring assert', () {
      check(() => lazySetBoxAround<Member, int>('tags', () async => box)).throws<AssertionError>();
    });

    scenario('an element type hive hands back untyped fails the wiring assert', () {
      // With an idOf, so this assert is the only one that can fire.
      int idOf(List<Object> elements) => elements.length;

      check(() => lazySetBoxAround<List<Person>, int>('tags', () async => box, idOf: idOf))
          .throws<AssertionError>();
      check(() => LazySetBox<List<Person>, int>('nested', idOf: idOf)).throws<AssertionError>();
      check(() => lazySetBoxAround<List<String>, int>('tags', () async => box, idOf: idOf))
          .returnsNormally();
    });

    scenario('the sync inspectors throw StateError before the first open, then work', () async {
      check(() => facade.length).throws<StateError>();
      check(() => facade.keys).throws<StateError>();
      check(() => facade.contains(1)).throws<StateError>();

      await facade.put(1, ['a']).run();

      check(facade.length).equals(1);
      check(facade.keys).deepEquals([1]);
      check(facade.contains(1)).isTrue();
    });

    scenario('the corruption gate throws at the call site, before the box even opens', () {
      check(() => facade.put(-1, ['a'])).throws<ArgumentError>();

      check(opener.count).equals(0);
    });
  });

  feature('LazySetBox aliasing contract', () {
    scenario('put copies: mutating the source afterwards never reaches the box', () async {
      final source = {'a'};

      await facade.put(1, source).run();
      source.add('rogue');

      check(await facade.getOr(1).run()).deepEquals({'a'});
    });

    scenario('reads reject mutation, present or absent', () async {
      await facade.put(1, ['a']).run();

      final present = await facade.getOr(1).run();
      final absent = await facade.getOr(9).run();

      check(() => present.add('rogue')).throws<UnsupportedError>();
      check(() => absent.add('rogue')).throws<UnsupportedError>();
    });

    scenario('update copies inward and hands back an unmodifiable view', () async {
      final mine = {'a'};

      await facade.update(1, (values) => values, ifAbsent: () => mine).run();
      mine.add('rogue');

      final result = await facade.update(1, (values) => {...values, 'b'}).run();

      check(() => result.add('rogue')).throws<UnsupportedError>();
      check(await facade.getOr(1).run()).deepEquals({'a', 'b'});
    });
  });

  feature('LazySetBox reads and absent vs stored-empty', () {
    scenario('an absent key is None, a stored empty set is Some(empty)', () async {
      check((await facade.get(1).run()).isNone()).isTrue();

      await facade.put(1, <String>[]).run();

      check((await facade.get(1).run()).toNullable()).isNotNull().isEmpty();
    });

    scenario('values reads every stored set', () async {
      await facade.putAll({
        1: ['a', 'a'],
        2: ['b', 'c'],
      }).run();

      check(await facade.values.run()).deepEquals([
        {'a'},
        {'b', 'c'},
      ]);
    });
  });

  feature('LazySetBox dedup on writes', () {
    scenario('value-type elements dedup by their own ==', () async {
      await facade.add(1, 'a').run();
      await facade.addAll(1, ['b', 'a']).run();

      check(await facade.getOr(1).run()).deepEquals({'a', 'b'});
    });

    scenario('put keeps the first element per id', () async {
      await members.put(1, [Member(1, 'first'), Member(1, 'second')]).run();

      check(await members.namesUnder(1)).deepEquals(['first']);
    });

    scenario('add keeps the stored element with the same id, and creates on absence', () async {
      await members.add(1, Member(1, 'stored')).run();
      await members.addAll(1, [Member(1, 'incoming'), Member(2, 'new')]).run();

      check(await members.namesUnder(1)).deepEquals(['stored', 'new']);
    });

    scenario(
      'upsert replaces in place, upsertAll appends new ids, both create on absence',
      () async {
        await members.upsert(1, Member(1, 'old')).run();
        await members.upsertAll(1, [Member(2, 'b'), Member(1, 'new')]).run();

        check(await members.namesUnder(1)).deepEquals(['new', 'b']);
      },
    );

    scenario("update's result is deduped by id", () async {
      await members.put(1, [Member(1, 'a')]).run();

      await members.update(1, (stored) => {...stored, Member(1, 'copy')}).run();

      check(await members.namesUnder(1)).deepEquals(['a']);
    });

    scenarioOutline<Future<Object> Function()>(
      'a write that keeps the stored set also drops an id stored twice, keeping the first',
      examples: {
        'add': () => members.add(1, Member(3, 'new')).run(),
        'upsert': () => members.upsert(1, Member(3, 'new')).run(),
        'remove': () => members.remove(1, Member(2, 'other')).run(),
        'update': () => members.update(1, (stored) => stored).run(),
      },
      outline: (write) async {
        // Written past the box, since its own writes never store an id twice.
        memberBox.store[1] = {Member(1, 'first'), Member(1, 'second'), Member(2, 'other')};

        await write();
        final readSet = await members.getOr(1).run();

        check(readSet.where((member) => member.id == 1).names).deepEquals(['first']);
      },
    );

    scenario('putAllGrouped groups by key, dedups each group, and replaces', () async {
      await members.put(2, [Member(9, 'old')]).run();

      await members.putAllGrouped([
        Member(1, 'a'),
        Member(10, 'bb'),
        Member(10, 'dd'),
        Member(20, 'cc'),
      ], keyOf: (member) => member.name.length).run();

      check(await members.namesUnder(1)).deepEquals(['a']);
      check(await members.namesUnder(2)).deepEquals(['bb', 'cc']);
    });
  });

  feature('LazySetBox remove', () {
    scenario(
      'remove matches a fresh copy by id, and the last one out leaves Some(empty)',
      () async {
        await members.put(1, [Member(1, 'a'), Member(2, 'b')]).run();

        await members.remove(1, Member(1, 'fresh copy')).run();
        check(await members.namesUnder(1)).deepEquals(['b']);

        await members.remove(1, Member(2, 'fresh copy')).run();
        check((await members.get(1).run()).toNullable()).isNotNull().isEmpty();
      },
    );

    scenario('remove is a no-op for an absent key or an absent element', () async {
      await facade.put(1, ['a']).run();
      observer.calls.clear();

      await facade.remove(9, 'a').run();
      await facade.remove(1, 'missing').run();

      check(observer.calls).isEmpty();
    });
  });

  feature('LazySetBox watch', () {
    scenario('writes carry Some of the view, deletes carry None', () async {
      final events = await recordEvents(facade.watch(), () async {
        await facade.put(1, ['a']).run();
        await facade.delete(1).run();
      });

      check(events).length.equals(2);
      check(events.first.value.toNullable()).isNotNull().deepEquals({'a'});
      check(() => events.first.value.toNullable()!.add('rogue')).throws<UnsupportedError>();
      check(events.last.value.isNone()).isTrue();
    });
  });

  feature('LazySetBox lifecycle', () {
    scenario('close before first use never opens, yet turns the handle terminal', () async {
      await facade.close().run();

      check(opener.count).equals(0);
      check(observer.calls).deepEquals(['closed:tags']);
      await check(facade.put(1, ['a']).run()).throws<HiveError>();
    });
  });
}
