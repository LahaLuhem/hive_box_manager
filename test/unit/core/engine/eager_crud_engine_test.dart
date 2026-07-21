// The eager engine against the stateful in-memory fake: CRUD, absence paths, observer
// dispatch, the sync corruption gate, Task laziness, and typed watch mapping.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/key/int_key_codec.dart';
import 'package:hive_box_manager/src/core/engine/eager_crud_engine.dart';
import 'package:hive_box_manager/src/core/value_codec/identity_value_codec.dart';
import 'package:hive_box_manager/src/event/typed_box_event.dart';
import 'package:hive_ce/hive.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/fake_boxes.dart';
import '../../../support/mocks.dart';
import '../../../support/recording_box_observer.dart';

void main() {
  late FakeEagerBox box;
  late RecordingBoxObserver observer;
  late EagerCrudEngine<String, int> engine;

  setUp(() {
    box = FakeEagerBox(name: 'users');
    observer = RecordingBoxObserver();
    engine = EagerCrudEngine(
      box: box,
      keyCodec: const IntKeyCodec(),
      valueCodec: const IdentityValueCodec(),
      observer: observer,
    );
  });

  feature('eager engine reads', () {
    scenario('an absent key reads as None and dispatches the miss', () {
      final result = engine.get(7);

      check(result.isNone()).isTrue();
      check(observer.calls).deepEquals(['read:users:7:null']);
    });

    scenario('a put value reads back as Some, decoded', () async {
      await engine.put(7, 'v').run();

      final result = engine.get(7);

      check(result.toNullable()).equals('v');
      check(observer.calls).deepEquals(['written:users:7:v', 'read:users:7:v']);
    });

    scenario('getOr falls back on absence and reads through on presence', () async {
      check(engine.getOr(7, 'fallback')).equals('fallback');

      await engine.put(7, 'v').run();

      check(engine.getOr(7, 'fallback')).equals('v');
    });

    scenario('values decodes lazily and dispatches one read-all with the count', () async {
      await engine.putAll({1: 'a', 2: 'b'}).run();
      observer.calls.clear();

      check(engine.values).deepEquals(['a', 'b']);
      check(observer.calls).deepEquals(['readAll:users:2']);
    });

    scenario('keys decode through the codec; contains and counts stay sync', () async {
      await engine.putAll({1: 'a', 2: 'b'}).run();

      check(engine.keys).deepEquals([1, 2]);
      check(engine.rawKeys).deepEquals([1, 2]);
      check(engine.contains(1)).isTrue();
      check(engine.contains(9)).isFalse();
      check(engine.length).equals(2);
      check(engine.isEmpty).isFalse();
      check(engine.isNotEmpty).isTrue();
      check(engine.name).equals('users');
    });
  });

  feature('eager engine writes', () {
    scenario('a Task is lazy: nothing is written until run', () async {
      final write = engine.put(7, 'v');

      check(box.store).isEmpty();

      await write.run();

      check(box.store).deepEquals({7: 'v'});
    });

    scenario('putAll writes the batch and dispatches one written-all with the count', () async {
      await engine.putAll({1: 'a', 2: 'b'}).run();

      check(box.store).deepEquals({1: 'a', 2: 'b'});
      check(observer.calls).deepEquals(['writtenAll:users:2']);
    });

    scenario('update rewrites a present value and returns the new one', () async {
      await engine.put(7, 'v').run();
      observer.calls.clear();

      final updated = await engine.update(7, (value) => '$value!').run();

      check(updated).equals('v!');
      check(box.store).deepEquals({7: 'v!'});
      check(observer.calls).deepEquals(['written:users:7:v!']);
    });

    scenario('update seeds an absent key through ifAbsent', () async {
      final seeded = await engine.update(7, (value) => '$value!', ifAbsent: () => 'seed').run();

      check(seeded).equals('seed');
      check(box.store).deepEquals({7: 'seed'});
    });

    scenario('update on an absent key without ifAbsent mirrors Map.update', () async {
      final update = engine.update(7, (value) => value);

      await check(update.run()).throws<ArgumentError>();
      check(box.store).isEmpty();
    });
  });

  feature('eager engine deletes', () {
    scenario('delete removes and dispatches; absent keys are silent no-ops', () async {
      await engine.put(7, 'v').run();
      observer.calls.clear();

      await engine.delete(7).run();
      await engine.delete(9).run();

      check(box.store).isEmpty();
      check(observer.calls).deepEquals(['deleted:users:7', 'deleted:users:9']);
    });

    scenario('deleteAll removes the batch and dispatches once per key', () async {
      await engine.putAll({1: 'a', 2: 'b', 3: 'c'}).run();
      observer.calls.clear();

      await engine.deleteAll([1, 3]).run();

      check(box.store).deepEquals({2: 'b'});
      check(observer.calls).deepEquals(['deleted:users:1', 'deleted:users:3']);
    });

    scenario('clear empties the box and dispatches the bulk event', () async {
      await engine.putAll({1: 'a', 2: 'b'}).run();
      observer.calls.clear();

      await engine.clear().run();

      check(box.store).isEmpty();
      check(observer.calls).deepEquals(['cleared:users']);
    });
  });

  feature('eager engine corruption gate', () {
    scenario('a non-storable key fails synchronously at the call site, before any Task', () {
      check(() => engine.put(-1, 'v')).throws<ArgumentError>();
      check(box.store).isEmpty();
    });

    scenario('one bad key in a batch fails the whole call before anything is written', () {
      check(() => engine.putAll({1: 'a', -1: 'b'})).throws<ArgumentError>();
      check(box.store).isEmpty();
    });
  });

  feature('eager engine watch', () {
    scenario('writes and deletes map to typed events; eager deletes carry the value', () async {
      final events = <TypedBoxEvent<String, int>>[];
      final subscription = engine.watch().listen(events.add);

      await engine.put(7, 'v').run();
      await engine.delete(7).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [
        TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: false),
        TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: true),
      ]);
    });

    scenario('a key filter narrows the stream to that key', () async {
      final events = <TypedBoxEvent<String, int>>[];
      final subscription = engine.watch(key: 2).listen(events.add);

      await engine.putAll({1: 'a', 2: 'b'}).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(
        events,
      ).deepEquals(const [TypedBoxEvent<String, int>(key: 2, value: 'b', deleted: false)]);
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
      await check(engine.put(7, 'v').run()).throws<HiveError>();
    });

    scenario('deleteFromDisk dispatches and empties the store', () async {
      await engine.put(7, 'v').run();
      observer.calls.clear();

      await engine.deleteFromDisk().run();

      check(box.deletedFromDisk).isTrue();
      check(observer.calls).deepEquals(['deletedFromDisk:users']);
    });

    scenario('an effect failure dispatches onOperationError and rethrows', () async {
      final failingBox = MockBox();
      when(failingBox.name).thenReturn('users');
      when(failingBox.put(any, any)).thenThrow(HiveError('disk gone'));
      final failing = EagerCrudEngine<String, int>(
        box: failingBox,
        keyCodec: const IntKeyCodec(),
        valueCodec: const IdentityValueCodec(),
        observer: observer,
      );

      await check(failing.put(7, 'v').run()).throws<HiveError>();
      check(observer.calls).deepEquals(['error:users:put:HiveError']);
    });

    scenario('no observer attached costs nothing and breaks nothing', () async {
      final silent = EagerCrudEngine<String, int>(
        box: FakeEagerBox(),
        keyCodec: const IntKeyCodec(),
        valueCodec: const IdentityValueCodec(),
      );

      await silent.put(7, 'v').run();

      check(silent.get(7).toNullable()).equals('v');
    });
  });
}
