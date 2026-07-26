// The eager engine against the stateful in-memory fake: CRUD, absence paths, observer dispatch, the
// sync corruption gate, Task laziness, and the raw watch passthrough.
//
// Calls spell out both key halves: the `RawKey` hive stores under, and the semantic key the observer
// hears. Typed watch events moved out to the façades with the key codec, and stay covered by the four
// façade suites.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/engine/eager_crud_engine.dart';
import 'package:hive_box_manager/src/core/raw_key.dart';
import 'package:hive_box_manager/src/core/value_codec/identity_value_codec.dart';
import 'package:hive_ce/hive.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/doubles/fake_boxes.dart';
import '../../../support/doubles/recording_box_observer.dart';
import '../../../support/mocks.dart';

/// One batch entry, in the shape the engine takes.
MapEntry<RawKey, String> entry(int key, String value) => MapEntry(RawKey(key), value);

/// Watch notifications as a comparable value (`BoxEvent` has no `==`).
(Object?, Object?, bool) shapeOf(BoxEvent event) => (event.key, event.value, event.deleted);

void main() {
  late FakeEagerBox box;
  late RecordingBoxObserver observer;
  late EagerCrudEngine<String> engine;

  setUp(() {
    box = FakeEagerBox(name: 'users');
    observer = RecordingBoxObserver();
    engine = EagerCrudEngine(box: box, valueCodec: const IdentityValueCodec(), observer: observer);
  });

  feature('eager engine reads', () {
    scenario('an absent key reads as None and dispatches the miss', () {
      final result = engine.get(const RawKey(7), 7);

      check(result.isNone()).isTrue();
      check(observer.calls).deepEquals(['read:users:7:null']);
    });

    scenario('a put value reads back as Some, decoded', () async {
      await engine.put(const RawKey(7), 7, 'v').run();

      final result = engine.get(const RawKey(7), 7);

      check(result.toNullable()).equals('v');
      check(observer.calls).deepEquals(['written:users:7:v', 'read:users:7:v']);
    });

    scenario('getOr falls back on absence and reads through on presence', () async {
      check(engine.getOr(const RawKey(7), 7, 'fallback')).equals('fallback');

      await engine.put(const RawKey(7), 7, 'v').run();

      check(engine.getOr(const RawKey(7), 7, 'fallback')).equals('v');
    });

    scenario('hive stores the raw key while the observer hears the semantic one', () async {
      await engine.put(const RawKey(7), 'user:7', 'v').run();
      engine.get(const RawKey(7), 'user:7');

      check(box.store).deepEquals({7: 'v'});
      check(observer.calls).deepEquals(['written:users:user:7:v', 'read:users:user:7:v']);
    });

    scenario('values decodes lazily and dispatches one read-all with the count', () async {
      await engine.putAll([entry(1, 'a'), entry(2, 'b')]).run();
      observer.calls.clear();

      check(engine.values).deepEquals(['a', 'b']);
      check(observer.calls).deepEquals(['readAll:users:2']);
    });

    scenario('raw keys, contains and the counts stay sync', () async {
      await engine.putAll([entry(1, 'a'), entry(2, 'b')]).run();

      check(engine.rawKeys).deepEquals([1, 2]);
      check(engine.contains(const RawKey(1))).isTrue();
      check(engine.contains(const RawKey(9))).isFalse();
      check(engine.length).equals(2);
      check(engine.isEmpty).isFalse();
      check(engine.isNotEmpty).isTrue();
      check(engine.name).equals('users');
    });
  });

  feature('eager engine writes', () {
    scenario('a Task is lazy: nothing is written until run', () async {
      final write = engine.put(const RawKey(7), 7, 'v');

      check(box.store).isEmpty();

      await write.run();

      check(box.store).deepEquals({7: 'v'});
    });

    scenario('putAll writes the batch and dispatches one written-all with the count', () async {
      await engine.putAll([entry(1, 'a'), entry(2, 'b')]).run();

      check(box.store).deepEquals({1: 'a', 2: 'b'});
      check(observer.calls).deepEquals(['writtenAll:users:2']);
    });

    scenario('update rewrites a present value and returns the new one', () async {
      await engine.put(const RawKey(7), 7, 'v').run();
      observer.calls.clear();

      final updated = await engine.update(const RawKey(7), 7, (value) => '$value!').run();

      check(updated).equals('v!');
      check(box.store).deepEquals({7: 'v!'});
      check(observer.calls).deepEquals(['written:users:7:v!']);
    });

    scenario('update seeds an absent key through ifAbsent', () async {
      final seeded = await engine
          .update(const RawKey(7), 7, (value) => '$value!', ifAbsent: () => 'seed')
          .run();

      check(seeded).equals('seed');
      check(box.store).deepEquals({7: 'seed'});
    });

    scenario('update on an absent key without ifAbsent mirrors Map.update', () async {
      final update = engine.update(const RawKey(7), 7, (value) => value);

      await check(update.run()).throws<ArgumentError>();
      check(box.store).isEmpty();
    });
  });

  feature('eager engine deletes', () {
    scenario('delete removes and dispatches; absent keys are silent no-ops', () async {
      await engine.put(const RawKey(7), 7, 'v').run();
      observer.calls.clear();

      await engine.delete(const RawKey(7), 7).run();
      await engine.delete(const RawKey(9), 9).run();

      check(box.store).isEmpty();
      check(observer.calls).deepEquals(['deleted:users:7', 'deleted:users:9']);
    });

    scenario('deleteAll removes the batch and dispatches once per key', () async {
      await engine.putAll([entry(1, 'a'), entry(2, 'b'), entry(3, 'c')]).run();
      observer.calls.clear();

      await engine.deleteAll([const RawKey(1), const RawKey(3)], [1, 3]).run();

      check(box.store).deepEquals({2: 'b'});
      check(observer.calls).deepEquals(['deleted:users:1', 'deleted:users:3']);
    });

    scenario('clear empties the box and dispatches the bulk event', () async {
      await engine.putAll([entry(1, 'a'), entry(2, 'b')]).run();
      observer.calls.clear();

      await engine.clear().run();

      check(box.store).isEmpty();
      check(observer.calls).deepEquals(['cleared:users']);
    });
  });

  feature('eager engine corruption gate', () {
    scenario('a non-storable key fails synchronously at the call site, before any Task', () {
      check(() => engine.put(const RawKey(-1), -1, 'v')).throws<ArgumentError>();
      check(box.store).isEmpty();
    });

    scenario('one bad key in a batch fails the whole call before anything is written', () {
      check(() => engine.putAll([entry(1, 'a'), entry(-1, 'b')])).throws<ArgumentError>();
      check(box.store).isEmpty();
    });
  });

  feature('eager engine watch', () {
    scenario('writes and deletes surface as raw events; eager deletes carry the value', () async {
      final events = <BoxEvent>[];
      final subscription = engine.watchRaw().listen(events.add);

      await engine.put(const RawKey(7), 7, 'v').run();
      await engine.delete(const RawKey(7), 7).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events.map(shapeOf)).deepEquals([(7, 'v', false), (7, 'v', true)]);
    });

    scenario('a key filter narrows the stream to that key', () async {
      final events = <BoxEvent>[];
      final subscription = engine.watchRaw(key: const RawKey(2)).listen(events.add);

      await engine.putAll([entry(1, 'a'), entry(2, 'b')]).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events.map(shapeOf)).deepEquals([(2, 'b', false)]);
    });
  });

  feature('eager engine lifecycle + failure dispatch', () {
    scenario('flush and compact delegate to the box', () async {
      await engine.flush().run();
      await engine.compact().run();

      check(box.flushCount).equals(1);
      check(box.compactCount).equals(1);
    });

    scenario('close is terminal: later effects surface the engine error (tier 3)', () async {
      await engine.close().run();

      check(observer.calls).deepEquals(['closed:users']);
      await check(engine.put(const RawKey(7), 7, 'v').run()).throws<HiveError>();
    });

    scenario('deleteFromDisk dispatches and empties the store', () async {
      await engine.put(const RawKey(7), 7, 'v').run();
      observer.calls.clear();

      await engine.deleteFromDisk().run();

      check(box.wasDeletedFromDisk).isTrue();
      check(observer.calls).deepEquals(['deletedFromDisk:users']);
    });

    scenario('an effect failure dispatches onOperationError and rethrows', () async {
      final failingBox = MockBox();
      when(failingBox.name).thenReturn('users');
      when(failingBox.put(any, any)).thenThrow(HiveError('disk gone'));
      final failing = EagerCrudEngine<String>(
        box: failingBox,
        valueCodec: const IdentityValueCodec(),
        observer: observer,
      );

      await check(failing.put(const RawKey(7), 7, 'v').run()).throws<HiveError>();
      check(observer.calls).deepEquals(['error:users:put:HiveError']);
    });

    scenario('no observer attached costs nothing and breaks nothing', () async {
      final silent = EagerCrudEngine<String>(
        box: FakeEagerBox(),
        valueCodec: const IdentityValueCodec(),
      );

      await silent.put(const RawKey(7), 7, 'v').run();

      check(silent.get(const RawKey(7), 7).toNullable()).equals('v');
    });
  });
}
