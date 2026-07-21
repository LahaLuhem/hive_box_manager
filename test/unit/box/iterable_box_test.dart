// The eager iterable façade against the stateful in-memory fake, wired through the
// same-library testing seam: the aliasing contract in both directions (private copies inward,
// unmodifiable views outward), absent-vs-empty, the add / addAll / remove sugar semantics, the
// sync corruption gate, and terminal lifecycle.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/iterable_box.dart';
import 'package:hive_box_manager/src/event/typed_box_event.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/date_key_codec.dart';
import '../../support/fake_boxes.dart';
import '../../support/recording_box_observer.dart';

void main() {
  late FakeEagerBox box;
  late RecordingBoxObserver observer;
  late IterableBox<String, int> facade;

  setUp(() {
    box = FakeEagerBox(name: 'tags');
    observer = RecordingBoxObserver();
    facade = iterableBoxAround(box, observer: observer);
  });

  feature('IterableBox wiring and codec defaulting', () {
    scenario('a custom codec owns the raw encoding and the decode round-trip', () async {
      final date = DateTime.utc(2026, 7, 21);
      final dateKeyed = iterableBoxAround<String, DateTime>(box, codec: const DateKeyCodec());

      await dateKeyed.put(date, ['a']).run();

      check(box.store.keys).deepEquals([date.toIso8601String()]);
      check(dateKeyed.keys).deepEquals([date]);
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(() => iterableBoxAround<String, DateTime>(box)).throws<AssertionError>();
    });
  });

  feature('IterableBox aliasing contract', () {
    scenario('put materialises: mutating the source afterwards never reaches the box', () async {
      final source = ['a'];

      await facade.put(1, source).run();
      source.add('rogue');

      check(facade.getOr(1)).deepEquals(['a']);
    });

    scenario('put accepts a lazy iterable and stores a plain list', () async {
      await facade.put(1, ['a', 'b'].map((tag) => tag.toUpperCase())).run();

      check(box.store[1]).isA<List<String>>();
      check(facade.getOr(1)).deepEquals(['A', 'B']);
    });

    scenario('returned lists reject mutation, present or absent', () async {
      await facade.put(1, ['a']).run();

      check(() => facade.getOr(1).add('rogue')).throws<UnsupportedError>();
      check(() => facade.getOr(9).add('rogue')).throws<UnsupportedError>();
    });

    scenario('update copies inward and hands back an unmodifiable view', () async {
      final mine = ['a'];

      await facade.update(1, (values) => values, ifAbsent: () => mine).run();
      mine.add('rogue');

      check(facade.getOr(1)).deepEquals(['a']);

      final result = await facade.update(1, (values) => [...values, 'b']).run();

      check(() => result.add('rogue')).throws<UnsupportedError>();
      check(facade.getOr(1)).deepEquals(['a', 'b']);
    });

    scenario('watch payloads carry the same unmodifiable views', () async {
      final events = <TypedBoxEvent<List<String>, int>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(1, ['a']).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).length.equals(1);
      check(events.first.value).deepEquals(['a']);
      check(() => events.first.value.add('rogue')).throws<UnsupportedError>();
    });
  });

  feature('IterableBox absent vs stored-empty', () {
    scenario('an absent key is None; a stored empty list is Some(empty)', () async {
      check(facade.get(1).isNone()).isTrue();

      await facade.put(1, <String>[]).run();

      check(facade.get(1).toNullable()).isNotNull().deepEquals(<String>[]);
      check(facade.contains(1)).isTrue();
    });
  });

  feature('IterableBox add, addAll, and remove sugar', () {
    scenario('add appends, creates on absence, and allows duplicates', () async {
      await facade.add(1, 'a').run();
      await facade.add(1, 'b').run();
      await facade.add(1, 'a').run();

      check(facade.getOr(1)).deepEquals(['a', 'b', 'a']);
    });

    scenario('addAll appends a batch and copies the source on absence', () async {
      final source = ['a', 'b'];

      await facade.addAll(1, source).run();
      source.add('rogue');
      await facade.addAll(1, ['c']).run();

      check(facade.getOr(1)).deepEquals(['a', 'b', 'c']);
    });

    scenario('remove drops the first occurrence only', () async {
      await facade.put(1, ['a', 'b', 'a']).run();

      await facade.remove(1, 'a').run();

      check(facade.getOr(1)).deepEquals(['b', 'a']);
    });

    scenario('removing the last element leaves Some(empty), never a deleted key', () async {
      await facade.put(1, ['a']).run();

      await facade.remove(1, 'a').run();

      check(facade.get(1).toNullable()).isNotNull().deepEquals(<String>[]);
      check(facade.contains(1)).isTrue();
    });

    scenario('remove is a no-op for an absent key or an absent element', () async {
      await facade.put(1, ['a']).run();
      observer.calls.clear();

      await facade.remove(9, 'a').run();
      await facade.remove(1, 'missing').run();

      // The reads dispatch; no write ever happens on either no-op path.
      check(observer.calls).deepEquals(['read:tags:9:null', 'read:tags:1:[a]']);
      check(facade.getOr(1)).deepEquals(['a']);
    });
  });

  feature('IterableBox keyed surface and failure paths', () {
    scenario('putAll materialises each list; inspectors and deletes behave keyed', () async {
      final source = ['b'];

      await facade.putAll({
        1: const ['a'],
        2: source,
      }).run();
      source.add('rogue');

      check(facade.values.map((values) => values.join())).deepEquals(['a', 'b']);
      check(facade.keys).deepEquals([1, 2]);
      check(facade.length).equals(2);
      check(facade.isNotEmpty).isTrue();

      await facade.delete(1).run();
      await facade.deleteAll([2]).run();
      await facade.clear().run();

      check(facade.isEmpty).isTrue();
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
