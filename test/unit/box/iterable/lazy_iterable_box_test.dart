// The lazy iterable façade against the stateful in-memory fake, wired through the same-library
// testing seam: auto-open, the sync-inspector carve-out, the aliasing contract on the lazy
// axis, absent-vs-empty, the sugar semantics, Option-valued watch payloads, and the
// pre-first-use close no-op rider.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/iterable/lazy_iterable_box.dart';
import 'package:hive_box_manager/src/event/lazy_typed_box_event.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/doubles/fake_boxes.dart';
import '../../../support/doubles/recording_box_observer.dart';

void main() {
  late FakeLazyBox box;
  late RecordingBoxObserver observer;
  late int openCalls;
  late LazyIterableBox<String, int> facade;

  setUp(() {
    box = FakeLazyBox(name: 'tags');
    observer = RecordingBoxObserver();
    openCalls = 0;
    facade = lazyIterableBoxAround('tags', () async {
      openCalls++;

      return box;
    }, observer: observer);
  });

  feature('LazyIterableBox wiring and auto-open', () {
    scenario('construction opens nothing; the first effect opens exactly once', () async {
      check(openCalls).equals(0);

      await facade.put(1, ['a']).run();
      await facade.put(2, ['b']).run();

      check(openCalls).equals(1);
      check(observer.calls.first).equals('opened:tags');
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(
        () => lazyIterableBoxAround<String, DateTime>('tags', () async => box),
      ).throws<AssertionError>();
    });

    scenario('the sync inspectors throw StateError before the first open, then work', () async {
      check(() => facade.length).throws<StateError>();
      check(() => facade.keys).throws<StateError>();
      check(() => facade.contains(1)).throws<StateError>();

      await facade.put(1, ['a']).run();

      check(facade.length).equals(1);
      check(facade.keys).deepEquals([1]);
      check(facade.contains(1)).isTrue();
      check(facade.isNotEmpty).isTrue();
      check(facade.isEmpty).isFalse();
    });

    scenario('the corruption gate throws at the call site, before the box even opens', () {
      check(() => facade.put(-1, ['a'])).throws<ArgumentError>();

      check(openCalls).equals(0);
    });
  });

  feature('LazyIterableBox aliasing contract', () {
    scenario('put materialises: mutating the source afterwards never reaches the box', () async {
      final source = ['a'];

      await facade.put(1, source).run();
      source.add('rogue');

      check(await facade.getOr(1).run()).deepEquals(['a']);
    });

    scenario('reads hand back unmodifiable views, present or absent', () async {
      await facade.put(1, ['a']).run();

      final present = await facade.getOr(1).run();
      final absent = await facade.getOr(9).run();

      check(() => present.add('rogue')).throws<UnsupportedError>();
      check(() => absent.add('rogue')).throws<UnsupportedError>();
    });

    scenario('update copies inward and hands back an unmodifiable view', () async {
      final mine = ['a'];

      await facade.update(1, (values) => values, ifAbsent: () => mine).run();
      mine.add('rogue');

      final result = await facade.update(1, (values) => [...values, 'b']).run();

      check(() => result.add('rogue')).throws<UnsupportedError>();
      check(await facade.getOr(1).run()).deepEquals(['a', 'b']);
    });
  });

  feature('LazyIterableBox reads and absent vs stored-empty', () {
    scenario('an absent key is None; a stored empty list is Some(empty)', () async {
      final absent = await facade.get(1).run();
      check(absent.isNone()).isTrue();

      await facade.put(1, <String>[]).run();

      final storedEmpty = await facade.get(1).run();
      check(storedEmpty.toNullable()).isNotNull().deepEquals(<String>[]);
    });

    scenario('values materialises every stored list', () async {
      await facade.putAll({
        1: ['a'],
        2: ['b', 'c'],
      }).run();

      final all = await facade.values.run();

      check(all).deepEquals([
        ['a'],
        ['b', 'c'],
      ]);
    });
  });

  feature('LazyIterableBox add, addAll, and remove sugar', () {
    scenario('add and addAll append (creating on absence); duplicates stay', () async {
      await facade.add(1, 'a').run();
      await facade.addAll(1, ['b', 'a']).run();

      check(await facade.getOr(1).run()).deepEquals(['a', 'b', 'a']);
    });

    scenario('remove drops the first occurrence; last-element removal leaves empty', () async {
      await facade.put(1, ['a', 'b', 'a']).run();

      await facade.remove(1, 'a').run();
      check(await facade.getOr(1).run()).deepEquals(['b', 'a']);

      await facade.remove(1, 'b').run();
      await facade.remove(1, 'a').run();

      final storedEmpty = await facade.get(1).run();
      check(storedEmpty.toNullable()).isNotNull().deepEquals(<String>[]);
      check(facade.contains(1)).isTrue();
    });

    scenario('remove is a no-op for an absent key or an absent element', () async {
      await facade.put(1, ['a']).run();

      await facade.remove(9, 'a').run();
      await facade.remove(1, 'missing').run();

      check(await facade.getOr(1).run()).deepEquals(['a']);
    });
  });

  feature('LazyIterableBox watch', () {
    scenario('writes carry Some of the view, deletes carry None', () async {
      final events = <LazyTypedBoxEvent<List<String>, int>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(1, ['a']).run();
      await facade.delete(1).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).length.equals(2);
      check(events.first.value.toNullable()).isNotNull().deepEquals(['a']);
      check(() => events.first.value.toNullable()!.add('rogue')).throws<UnsupportedError>();
      check(events.last.value.isNone()).isTrue();
      check(events.last.deleted).isTrue();
    });
  });

  feature('LazyIterableBox lifecycle', () {
    scenario('close before first use never opens, yet turns the handle terminal', () async {
      await facade.close().run();

      check(openCalls).equals(0);
      check(observer.calls).deepEquals(['closed:tags']);
      await check(facade.put(1, ['a']).run()).throws<HiveError>();
    });
  });
}
