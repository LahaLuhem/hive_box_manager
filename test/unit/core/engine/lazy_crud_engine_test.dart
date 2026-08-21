// The lazy engine against the stateful in-memory fake: single-flight auto-open (the named
// Phase 1 race test), CRUD + absence paths, the sync gate firing before the box even opens,
// the raw watch passthrough, and the terminal-close contract.
//
// Calls spell out both key halves: the `RawKey` hive stores under, and the semantic key the
// observer hears. Option-valued watch events moved out to the façades with the key codec.
@Tags(['unit'])
library;

import 'dart:async';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/engine/lazy_crud_engine.dart';
import 'package:hive_box_manager/src/core/raw_key.dart';
import 'package:hive_box_manager/src/core/value_codec/identity_value_codec.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/doubles/fake_boxes.dart';
import '../../../support/doubles/recording_box_observer.dart';

/// One batch entry, in the shape the engine takes.
MapEntry<RawKey, String> entry(int key, String value) => MapEntry(RawKey(key), value);

/// Watch notifications as a comparable value (`BoxEvent` has no `==`).
(Object?, Object?, bool) shapeOf(BoxEvent event) => (event.key, event.value, event.deleted);

void main() {
  late FakeLazyBox box;
  late RecordingBoxObserver observer;
  late int openCalls;

  LazyCrudEngine<String> makeEngine({Future<LazyBox<Object?>> Function()? openBox}) =>
      LazyCrudEngine(
        boxName: 'logs',
        openBox:
            openBox ??
            () async {
              openCalls++;

              return box;
            },
        valueCodec: const IdentityValueCodec(),
        observer: observer,
      );

  setUp(() {
    box = FakeLazyBox(name: 'logs');
    observer = RecordingBoxObserver();
    openCalls = 0;
  });

  feature('lazy engine auto-open', () {
    scenario('the first effect opens the box exactly once and dispatches it', () async {
      final engine = makeEngine();

      await engine.put(const RawKey(7), 7, 'v').run();
      await engine.put(const RawKey(8), 8, 'w').run();

      check(openCalls).equals(1);
      check(observer.calls).deepEquals(['opened:logs', 'written:logs:7:v', 'written:logs:8:w']);
    });

    scenario('N concurrent first operations share one single-flight open', () async {
      final gate = Completer<void>();
      final engine = makeEngine(
        openBox: () async {
          openCalls++;
          await gate.future;

          return box;
        },
      );

      // Concurrency is the point here: every op fires before the open completes.
      final racing = [
        engine.put(const RawKey(1), 1, 'a').run(),
        engine.put(const RawKey(2), 2, 'b').run(),
        engine.get(const RawKey(1), 1).run(),
        engine.values().run(),
        engine.ensureInitialised().run(),
      ];
      check(openCalls).equals(1);

      gate.complete();
      await racing.wait;

      check(openCalls).equals(1);
    });

    scenario('a failed open resets the memo so the next operation retries', () async {
      var attempts = 0;
      final engine = makeEngine(
        openBox: () async {
          attempts++;
          if (attempts == 1) throw HiveError('locked');

          return box;
        },
      );

      await check(engine.put(const RawKey(7), 7, 'v').run()).throws<HiveError>();
      await engine.put(const RawKey(7), 7, 'v').run();

      check(attempts).equals(2);
      check(observer.calls).deepEquals([
        'error:logs:open:HiveError',
        'error:logs:put:HiveError',
        'opened:logs',
        'written:logs:7:v',
      ]);
    });

    scenario('the sync inspectors demand an opened box, then work', () async {
      final engine = makeEngine();

      check(() => engine.length).throws<StateError>();
      check(() => engine.rawKeys).throws<StateError>();
      check(() => engine.contains(const RawKey(7))).throws<StateError>();

      await engine.ensureInitialised().run();
      await engine.put(const RawKey(7), 7, 'v').run();

      check(engine.length).equals(1);
      check(engine.isEmpty).isFalse();
      check(engine.isNotEmpty).isTrue();
      check(engine.rawKeys).deepEquals([7]);
      check(engine.contains(const RawKey(7))).isTrue();
      check(engine.name).equals('logs');
    });
  });

  feature('lazy engine reads', () {
    scenario('an absent key reads as None and dispatches the miss', () async {
      final engine = makeEngine();

      final result = await engine.get(const RawKey(7), 7).run();

      check(result.isNone()).isTrue();
      check(observer.calls).deepEquals(['opened:logs', 'read:logs:7:null']);
    });

    scenario('a put value reads back as Some, decoded', () async {
      final engine = makeEngine();
      await engine.put(const RawKey(7), 7, 'v').run();

      final result = await engine.get(const RawKey(7), 7).run();

      check(result.toNullable()).equals('v');
    });

    scenario('getOr falls back on absence and reads through on presence', () async {
      final engine = makeEngine();

      check(await engine.getOr(const RawKey(7), 7, 'fallback').run()).equals('fallback');

      await engine.put(const RawKey(7), 7, 'v').run();

      check(await engine.getOr(const RawKey(7), 7, 'fallback').run()).equals('v');
    });

    scenario('values materialises every stored value', () async {
      final engine = makeEngine();
      await engine.putAll([entry(1, 'a'), entry(2, 'b')]).run();
      observer.calls.clear();

      final values = await engine.values().run();

      check(values).deepEquals(['a', 'b']);
      check(observer.calls).deepEquals(['readAll:logs:2']);
    });
  });

  feature('lazy engine writes and deletes', () {
    scenario('a Task is lazy: nothing opens or writes until run', () async {
      final engine = makeEngine();
      final write = engine.put(const RawKey(7), 7, 'v');

      check(openCalls).equals(0);
      check(box.store).isEmpty();

      await write.run();

      check(box.store).deepEquals({7: 'v'});
    });

    scenario('the corruption gate fires at the call site, before the box even opens', () {
      final engine = makeEngine();

      check(() => engine.put(const RawKey(-1), -1, 'v')).throws<ArgumentError>();
      check(() => engine.putAll([entry(1, 'a'), entry(-1, 'b')])).throws<ArgumentError>();
      check(openCalls).equals(0);
    });

    scenario('two entries encoding to one raw key trip the duplicate assert', () {
      final engine = makeEngine();

      check(() => engine.putAll([entry(1, 'a'), entry(1, 'b')])).throws<AssertionError>();

      check(openCalls).equals(0);
      check(box.store).isEmpty();
    });

    scenario('update rewrites, seeds via ifAbsent, and mirrors Map.update on absence', () async {
      final engine = makeEngine();
      await engine.put(const RawKey(7), 7, 'v').run();

      check(await engine.update(const RawKey(7), 7, (value) => '$value!').run()).equals('v!');
      check(await engine.update(const RawKey(9), 9, (value) => value, ifAbsent: () => 'seed').run())
          .equals('seed');
      await check(engine.update(const RawKey(8), 8, (value) => value).run())
          .throws<ArgumentError>();
    });

    scenario('deleteAll and clear remove batches with per-key and bulk dispatch', () async {
      final engine = makeEngine();
      await engine.putAll([entry(1, 'a'), entry(2, 'b'), entry(3, 'c')]).run();
      observer.calls.clear();

      await engine.deleteAll([const RawKey(1), const RawKey(2)], [1, 2]).run();
      await engine.clear().run();

      check(box.store).isEmpty();
      check(observer.calls).deepEquals(['deleted:logs:1', 'deleted:logs:2', 'cleared:logs']);
    });
  });

  feature('lazy engine watch', () {
    scenario('raw events pass through; a lazy delete carries no value', () async {
      final engine = makeEngine();
      final events = <BoxEvent>[];
      final subscription = engine.watchRaw().listen(events.add);
      await pumpEventQueue();

      await engine.put(const RawKey(7), 7, 'v').run();
      await engine.delete(const RawKey(7), 7).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events.map(shapeOf)).deepEquals([(7, 'v', false), (7, null, true)]);
    });

    scenario('a key filter narrows the stream to that key', () async {
      final engine = makeEngine();
      final events = <BoxEvent>[];
      final subscription = engine.watchRaw(key: const RawKey(2)).listen(events.add);
      await pumpEventQueue();

      await engine.putAll([entry(1, 'a'), entry(2, 'b')]).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events.map(shapeOf)).deepEquals([(2, 'b', false)]);
    });
  });

  feature('lazy engine lifecycle', () {
    scenario('flush and compact delegate to the box', () async {
      final engine = makeEngine();

      await engine.flush().run();
      await engine.compact().run();

      check(box.flushCount).equals(1);
      check(box.compactCount).equals(1);
    });

    scenario('close before first use never opens, yet turns the handle terminal', () async {
      final engine = makeEngine();

      await engine.close().run();

      check(openCalls).equals(0);
      check(observer.calls).deepEquals(['closed:logs']);

      await check(engine.put(const RawKey(7), 7, 'v').run()).throws<HiveError>();
      check(() => engine.length).throws<HiveError>();
      check(observer.calls.last).equals('error:logs:put:HiveError');
    });

    scenario('a second close before first use stays benign', () async {
      final engine = makeEngine();

      await engine.close().run();
      await engine.close().run();

      check(openCalls).equals(0);
      check(observer.calls).deepEquals(['closed:logs', 'closed:logs']);
    });

    scenario('close after use closes the real box and is terminal (tier 3)', () async {
      final engine = makeEngine();
      await engine.put(const RawKey(7), 7, 'v').run();

      await engine.close().run();

      check(box.isClosed).isTrue();
      await check(engine.get(const RawKey(7), 7).run()).throws<HiveError>();
      check(
        observer.calls,
      ).deepEquals(['opened:logs', 'written:logs:7:v', 'closed:logs', 'error:logs:get:HiveError']);
    });

    scenario('deleteFromDisk dispatches and empties the store', () async {
      final engine = makeEngine();
      await engine.put(const RawKey(7), 7, 'v').run();
      observer.calls.clear();

      await engine.deleteFromDisk().run();

      check(box.wasDeletedFromDisk).isTrue();
      check(observer.calls).deepEquals(['deletedFromDisk:logs']);
    });
  });
}
