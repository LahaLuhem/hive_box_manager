@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/set/set_box.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  late FakeEagerBox box;
  late RecordingBoxObserver observer;
  late SetBox<String, int> facade;
  late SetBox<Member, int> members;
  late FakeEagerBox memberBox;

  setUp(() {
    box = FakeEagerBox(name: 'tags');
    observer = RecordingBoxObserver();
    facade = setBoxAround(box, observer: observer);
    memberBox = FakeEagerBox(name: 'members');
    members = setBoxAround(memberBox, idOf: (member) => member.id);
  });

  feature('SetBox wiring', () {
    scenario('a custom codec owns the raw encoding and the decode round-trip', () async {
      final date = DateTime.utc(2026, 7, 21);
      final dateKeyed = setBoxAround<String, DateTime>(box, codec: const DateKeyCodec());

      await dateKeyed.put(date, ['a']).run();

      check(box.store.keys).deepEquals([date.toIso8601String()]);
      check(dateKeyed.keys).deepEquals([date]);
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(() => setBoxAround<String, DateTime>(box)).throws<AssertionError>();
    });

    scenario('a custom element type without idOf fails the wiring assert', () {
      check(() => setBoxAround<Member, int>(box)).throws<AssertionError>();
    });
  });

  feature('SetBox aliasing contract', () {
    scenario('put copies: mutating the source afterwards never reaches the box', () async {
      final source = {'a'};

      await facade.put(1, source).run();
      source.add('rogue');

      check(facade.getOr(1)).deepEquals({'a'});
    });

    scenario('put accepts a lazy iterable and stores a plain set', () async {
      await facade.put(1, ['a', 'b'].map((tag) => tag.toUpperCase())).run();

      check(box.store[1]).isA<Set<String>>();
      check(facade.getOr(1)).deepEquals({'A', 'B'});
    });

    scenario('returned sets reject mutation, present or absent', () async {
      await facade.put(1, ['a']).run();

      check(() => facade.getOr(1).add('rogue')).throws<UnsupportedError>();
      check(() => facade.getOr(9).add('rogue')).throws<UnsupportedError>();
    });

    scenario('update copies inward and hands back an unmodifiable view', () async {
      final mine = {'a'};

      await facade.update(1, (values) => values, ifAbsent: () => mine).run();
      mine.add('rogue');

      check(facade.getOr(1)).deepEquals({'a'});

      final result = await facade.update(1, (values) => {...values, 'b'}).run();

      check(() => result.add('rogue')).throws<UnsupportedError>();
      check(facade.getOr(1)).deepEquals({'a', 'b'});
    });

    scenario('watch payloads carry the same unmodifiable views', () async {
      final events = await recordEvents(facade.watch(), () => facade.put(1, ['a']).run());

      check(events).length.equals(1);
      check(events.first.value).deepEquals({'a'});
      check(() => events.first.value.add('rogue')).throws<UnsupportedError>();
    });
  });

  feature('SetBox absent vs stored-empty', () {
    scenario('an absent key is None, a stored empty set is Some(empty)', () async {
      check(facade.get(1).isNone()).isTrue();

      await facade.put(1, <String>[]).run();

      check(facade.get(1).toNullable()).isNotNull().isEmpty();
      check(facade.contains(1)).isTrue();
    });
  });

  feature('SetBox dedup on writes', () {
    scenario('value-type elements dedup by their own ==', () async {
      await facade.put(1, ['a', 'b', 'a']).run();
      await facade.add(1, 'b').run();

      check(facade.getOr(1)).deepEquals({'a', 'b'});
    });

    scenario('put keeps the first element per id', () async {
      await members.put(1, [Member(1, 'first'), Member(1, 'second')]).run();

      check(members.getOr(1).names).deepEquals(['first']);
    });

    scenario('add keeps the stored element with the same id, and creates on absence', () async {
      await members.add(1, Member(1, 'stored')).run();
      await members.add(1, Member(1, 'incoming')).run();
      await members.add(1, Member(2, 'new')).run();

      check(members.getOr(1).names).deepEquals(['stored', 'new']);
    });

    scenario('addAll keeps stored elements and appends new ids in order', () async {
      await members.put(1, [Member(1, 'stored')]).run();

      await members.addAll(1, [Member(3, 'c'), Member(1, 'incoming'), Member(2, 'b')]).run();

      check(members.getOr(1).names).deepEquals(['stored', 'c', 'b']);
    });

    scenario('upsert replaces the stored element with the same id where it sits', () async {
      await members.put(1, [Member(1, 'a'), Member(2, 'old'), Member(3, 'c')]).run();

      await members.upsert(1, Member(2, 'new')).run();

      check(members.getOr(1).names).deepEquals(['a', 'new', 'c']);
    });

    scenario('upsertAll replaces in place, appends new ids, and creates on absence', () async {
      await members.upsertAll(9, [Member(1, 'only')]).run();
      await members.put(1, [Member(1, 'old')]).run();

      await members.upsertAll(1, [Member(2, 'b'), Member(1, 'new')]).run();

      check(members.getOr(9).names).deepEquals(['only']);
      check(members.getOr(1).names).deepEquals(['new', 'b']);
    });

    scenario("update's result is deduped by id", () async {
      await members.put(1, [Member(1, 'a')]).run();

      await members.update(1, (stored) => {...stored, Member(1, 'copy')}).run();

      check(members.getOr(1).names).deepEquals(['a']);
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

        check(members.getOr(1).where((member) => member.id == 1).names).deepEquals(['first']);
      },
    );
  });

  feature('SetBox remove', () {
    scenario('remove matches a fresh copy by id', () async {
      await members.put(1, [Member(1, 'a'), Member(2, 'b')]).run();

      await members.remove(1, Member(1, 'fresh copy')).run();

      check(members.getOr(1).names).deepEquals(['b']);
    });

    scenario('removing the last element leaves Some(empty), never a deleted key', () async {
      await facade.put(1, ['a']).run();

      await facade.remove(1, 'a').run();

      check(facade.get(1).toNullable()).isNotNull().isEmpty();
      check(facade.contains(1)).isTrue();
    });

    scenario('remove is a no-op for an absent key or an absent element', () async {
      await facade.put(1, ['a']).run();
      observer.calls.clear();

      await facade.remove(9, 'a').run();
      await facade.remove(1, 'missing').run();

      check(observer.calls).isEmpty();
      check(facade.getOr(1)).deepEquals({'a'});
    });
  });

  feature('SetBox keyed surface and failure paths', () {
    scenario('putAll dedups each set; inspectors and deletes behave keyed', () async {
      await facade.putAll({
        1: const ['a', 'a'],
        2: const ['b'],
      }).run();

      check(facade.values.map((values) => values.join())).deepEquals(['a', 'b']);
      check(facade.keys).deepEquals([1, 2]);
      check(facade.length).equals(2);

      await facade.delete(1).run();
      await facade.deleteAll([2]).run();
      await facade.clear().run();

      check(facade.isEmpty).isTrue();
    });

    scenario('putAllGrouped groups by key, dedups each group, and replaces', () async {
      await members.put(2, [Member(9, 'old')]).run();

      await members.putAllGrouped([
        Member(1, 'a'),
        Member(10, 'bb'),
        Member(10, 'dd'),
        Member(20, 'cc'),
      ], keyOf: (member) => member.name.length).run();

      check(members.getOr(1).names).deepEquals(['a']);
      check(members.getOr(2).names).deepEquals(['bb', 'cc']);
    });

    scenario('the corruption gate throws at the call site and nothing is written', () {
      check(() => facade.put(-1, ['a'])).throws<ArgumentError>();
      check(
        () => facade.putAll({
          -1: const ['a'],
        }),
      ).throws<ArgumentError>();

      check(box.store).isEmpty();
    });

    scenario('close is terminal: sync reads and later effects surface hive errors', () async {
      await facade.put(1, ['a']).run();

      await facade.close().run();

      check(() => facade.get(1)).throws<HiveError>();
      await check(facade.add(1, 'b').run()).throws<HiveError>();
    });
  });
}
