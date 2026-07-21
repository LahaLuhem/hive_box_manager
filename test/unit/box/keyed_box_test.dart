// The eager façade against the stateful in-memory fake, wired through the same-library testing
// seam: codec defaulting at construction, delegation and event mapping per member, the sync
// corruption gate, absence + failure paths, and the terminal-close contract.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/keyed_box.dart';
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
  late KeyedBox<String, int> facade;

  setUp(() {
    box = FakeEagerBox(name: 'users');
    observer = RecordingBoxObserver();
    facade = keyedBoxAround(box, observer: observer);
  });

  feature('KeyedBox wiring and codec defaulting', () {
    scenario('int keys pass through the identity default untouched', () async {
      await facade.put(7, 'v').run();

      check(box.store).deepEquals({7: 'v'});
      check(facade.keys).deepEquals([7]);
    });

    scenario('String keys pass through the identity default untouched', () async {
      final stringKeyed = keyedBoxAround<String, String>(FakeEagerBox());

      await stringKeyed.put('k', 'v').run();

      check(stringKeyed.get('k').toNullable()).equals('v');
    });

    scenario('a custom codec owns the raw encoding and the decode round-trip', () async {
      final date = DateTime.utc(2026, 7, 21);
      final dateKeyed = keyedBoxAround<String, DateTime>(box, codec: const DateKeyCodec());

      await dateKeyed.put(date, 'v').run();

      check(box.store.keys).deepEquals([date.toIso8601String()]);
      check(dateKeyed.keys).deepEquals([date]);
      check(dateKeyed.get(date).toNullable()).equals('v');
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(() => keyedBoxAround<String, DateTime>(box)).throws<AssertionError>();
    });
  });

  feature('KeyedBox reads', () {
    scenario('an absent key reads as None, falls back through getOr, and is not contained', () {
      check(facade.get(7).isNone()).isTrue();
      check(facade.getOr(7, 'fallback')).equals('fallback');
      check(facade.contains(7)).isFalse();
    });

    scenario('stored entries surface through every inspector, decoded', () async {
      await facade.putAll({1: 'a', 2: 'b'}).run();

      check(facade.get(1).toNullable()).equals('a');
      check(facade.getOr(1, 'fallback')).equals('a');
      check(facade.contains(1)).isTrue();
      check(facade.values).deepEquals(['a', 'b']);
      check(facade.keys).deepEquals([1, 2]);
      check(facade.length).equals(2);
      check(facade.isEmpty).isFalse();
      check(facade.isNotEmpty).isTrue();
      check(facade.name).equals('users');
    });
  });

  feature('KeyedBox writes', () {
    scenario('a write Task is lazy: nothing lands until run', () async {
      final write = facade.put(7, 'v');

      check(box.store).isEmpty();

      await write.run();

      check(box.store).deepEquals({7: 'v'});
    });

    scenario('the corruption gate throws at the call site and nothing is written', () {
      check(() => facade.put(-1, 'v')).throws<ArgumentError>();
      check(() => facade.putAll({1: 'a', -1: 'b'})).throws<ArgumentError>();

      check(box.store).isEmpty();
      check(observer.calls).isEmpty();
    });

    scenario('update rewrites, seeds via ifAbsent, and mirrors Map.update on absence', () async {
      await facade.put(7, 'v').run();

      check(await facade.update(7, (value) => '$value!').run()).equals('v!');
      check(await facade.update(9, (value) => value, ifAbsent: () => 'seed').run()).equals('seed');
      await check(facade.update(8, (value) => value).run()).throws<ArgumentError>();
    });

    scenario('delete, deleteAll, and clear remove entries with per-key dispatch', () async {
      await facade.putAll({1: 'a', 2: 'b', 3: 'c', 4: 'd'}).run();
      observer.calls.clear();

      await facade.delete(1).run();
      await facade.deleteAll([2, 3]).run();
      await facade.clear().run();

      check(box.store).isEmpty();
      check(
        observer.calls,
      ).deepEquals(['deleted:users:1', 'deleted:users:2', 'deleted:users:3', 'cleared:users']);
    });
  });

  feature('KeyedBox watch', () {
    scenario('events are typed and deletes still carry the value (eager promise)', () async {
      final events = <TypedBoxEvent<String, int>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(7, 'v').run();
      await facade.delete(7).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [
        TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: false),
        TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: true),
      ]);
    });

    scenario('a key filter narrows the stream to that key', () async {
      final events = <TypedBoxEvent<String, int>>[];
      final subscription = facade.watch(key: 2).listen(events.add);
      await pumpEventQueue();

      await facade.putAll({1: 'a', 2: 'b'}).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(
        events,
      ).deepEquals(const [TypedBoxEvent<String, int>(key: 2, value: 'b', deleted: false)]);
    });
  });

  feature('KeyedBox lifecycle and failure paths', () {
    scenario('flush and compact delegate to the box', () async {
      await facade.flush().run();
      await facade.compact().run();

      check(box.flushCount).equals(1);
      check(box.compactCount).equals(1);
    });

    scenario('close is terminal: sync reads and later effects surface hive errors', () async {
      await facade.put(7, 'v').run();
      observer.calls.clear();

      await facade.close().run();

      check(() => facade.get(7)).throws<HiveError>();
      await check(facade.put(8, 'w').run()).throws<HiveError>();
      check(observer.calls).deepEquals(['closed:users', 'error:users:put:HiveError']);
    });

    scenario('deleteFromDisk is terminal and reaches storage', () async {
      await facade.put(7, 'v').run();
      observer.calls.clear();

      await facade.deleteFromDisk().run();

      check(box.deletedFromDisk).isTrue();
      check(box.store).isEmpty();
      check(observer.calls).deepEquals(['deletedFromDisk:users']);
    });

    scenario('the observer hears the whole flow in dispatch order', () async {
      await facade.put(7, 'v').run();
      check(facade.get(7).toNullable()).equals('v');
      await facade.delete(7).run();

      check(observer.calls).deepEquals(['written:users:7:v', 'read:users:7:v', 'deleted:users:7']);
    });
  });
}
