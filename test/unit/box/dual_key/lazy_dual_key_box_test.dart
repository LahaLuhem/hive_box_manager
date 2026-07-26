// The lazy dual-key façade against the stateful in-memory fake, wired through the same-library
// testing seam: auto-open (queries included), the sync-inspector carve-out, codec defaulting,
// record round-trips, Task-shaped queries (empty list, never None), Option-valued watch
// payloads, and the pre-first-use close no-op rider.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/src/box/dual_key/lazy_dual_key_box.dart';
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
  late LazyDualKeyBox<String, int, int> facade;

  setUp(() {
    box = FakeLazyBox(name: 'grid');
    observer = RecordingBoxObserver();
    openCalls = 0;
    facade = lazyDualKeyBoxAround('grid', () async {
      openCalls++;

      return box;
    }, observer: observer);
  });

  feature('LazyDualKeyBox wiring and auto-open', () {
    scenario('construction opens nothing; the first effect opens and stores composite', () async {
      check(openCalls).equals(0);

      await facade.put(7, 9, 'v').run();

      check(openCalls).equals(1);
      check(box.store).deepEquals({'7:9': 'v'});
    });

    scenario('a query auto-opens like any other effect', () async {
      check(openCalls).equals(0);

      final matches = await facade.queryByPrimary(1).run();

      check(openCalls).equals(1);
      check(matches).isEmpty();
    });

    scenario('non-(int, int) parts without a codec fail the wiring assert', () {
      check(
        () => lazyDualKeyBoxAround<String, DateTime, int>('grid', () async => box),
      ).throws<AssertionError>();
    });

    scenario('the sync inspectors throw StateError before the first open, then work', () async {
      check(() => facade.length).throws<StateError>();
      check(() => facade.keys).throws<StateError>();
      check(() => facade.contains(1, 2)).throws<StateError>();
      check(facade.name).equals('grid');

      await facade.put(1, 2, 'v').run();

      check(facade.length).equals(1);
      check(facade.keys).deepEquals([(1, 2)]);
      check(facade.contains(1, 2)).isTrue();
      check(facade.isNotEmpty).isTrue();
      check(facade.isEmpty).isFalse();
    });
  });

  feature('LazyDualKeyBox reads and queries', () {
    scenario('absent composite keys read as None and fall back through getOr', () async {
      final absent = await facade.get(1, 2).run();

      check(absent.isNone()).isTrue();
      check(await facade.getOr(1, 2, 'fallback').run()).equals('fallback');
    });

    scenario('stored entries read back as Some, through getOr, and via values', () async {
      await facade.putAll({(1, 1): 'a', (2, 2): 'b'}).run();

      final present = await facade.get(1, 1).run();

      check(present.toNullable()).equals('a');
      check(await facade.getOr(1, 1, 'fallback').run()).equals('a');
      check(await facade.values.run()).deepEquals(['a', 'b']);
    });

    scenario('queries return plain empty lists when nothing matches, never None', () async {
      final matches = await facade.queryByPrimary(42).run();

      check(matches).isA<List<String>>();
      check(matches).isEmpty();
    });

    scenario('queries collect every match by the requested part', () async {
      await facade.putAll({(1, 1): 'a', (1, 2): 'b', (2, 1): 'c'}).run();

      check(await facade.queryByPrimary(1).run()).deepEquals(['a', 'b']);
      check(await facade.queryBySecondary(1).run()).deepEquals(['a', 'c']);

      await facade.delete(1, 1).run();

      check(await facade.queryByPrimary(1).run()).deepEquals(['b']);
    });
  });

  feature('LazyDualKeyBox writes', () {
    scenario('update rewrites, seeds via ifAbsent, and mirrors Map.update on absence', () async {
      await facade.put(1, 1, 'v').run();

      check(await facade.update(1, 1, (value) => '$value!').run()).equals('v!');
      check(
        await facade.update(9, 9, (value) => value, ifAbsent: () => 'seed').run(),
      ).equals('seed');
      await check(facade.update(8, 8, (value) => value).run()).throws<ArgumentError>();
    });

    scenario('putAllBy keys each value through both extractors', () async {
      await facade
          .putAllBy(
            ['a', 'bb', 'ccc'],
            primary: (value) => value.length,
            secondary: (value) => value.codeUnitAt(0),
          )
          .run();

      check(await facade.get(2, 98).run()).equals(const Some('bb'));
      check(facade.keys).deepEquals([(1, 97), (2, 98), (3, 99)]);
    });

    scenario('putAllBy trips the duplicate assert before the box even opens', () {
      check(
        () => facade.putAllBy(
          ['ab', 'cd'],
          primary: (value) => value.length,
          secondary: (value) => value.length,
        ),
      ).throws<AssertionError>();

      check(box.store).isEmpty();
    });

    scenario('delete, deleteAll, and clear remove entries', () async {
      await facade.putAll({(1, 1): 'a', (2, 2): 'b', (3, 3): 'c'}).run();

      await facade.delete(1, 1).run();
      await facade.deleteAll([(2, 2)]).run();
      await facade.clear().run();

      check(box.store).isEmpty();
    });
  });

  feature('LazyDualKeyBox watch', () {
    scenario('writes carry Some with record keys, deletes carry None', () async {
      final events = <LazyTypedBoxEvent<String, (int, int)>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(1, 2, 'v').run();
      await facade.delete(1, 2).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [
        LazyTypedBoxEvent<String, (int, int)>(key: (1, 2), value: Some('v')),
        LazyTypedBoxEvent<String, (int, int)>(key: (1, 2), value: None()),
      ]);
      check(events.last.deleted).isTrue();
    });
  });

  feature('LazyDualKeyBox lifecycle', () {
    scenario('close before first use never opens, yet turns the handle terminal', () async {
      await facade.close().run();

      check(openCalls).equals(0);
      check(observer.calls).deepEquals(['closed:grid']);
      await check(facade.put(1, 2, 'v').run()).throws<HiveError>();
      await check(facade.queryByPrimary(1).run()).throws<HiveError>();
    });
  });
}
