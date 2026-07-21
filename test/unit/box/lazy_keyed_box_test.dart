// The lazy façade against the stateful in-memory fake, wired through the same-library testing
// seam: single-flight auto-open, the sync-inspector carve-out, codec defaulting, delegation per
// member, Option-valued watch events, absence + failure paths, and the pre-first-use close
// no-op rider.
@Tags(['unit'])
library;

import 'dart:async';

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/src/box/lazy_keyed_box.dart';
import 'package:hive_box_manager/src/event/lazy_typed_box_event.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/date_key_codec.dart';
import '../../support/fake_boxes.dart';
import '../../support/recording_box_observer.dart';

void main() {
  late FakeLazyBox box;
  late RecordingBoxObserver observer;
  late int openCalls;
  late LazyKeyedBox<String, int> facade;

  setUp(() {
    box = FakeLazyBox(name: 'logs');
    observer = RecordingBoxObserver();
    openCalls = 0;
    facade = lazyKeyedBoxAround('logs', () async {
      openCalls++;

      return box;
    }, observer: observer);
  });

  feature('LazyKeyedBox wiring and codec defaulting', () {
    scenario('int keys pass through the identity default untouched', () async {
      await facade.put(7, 'v').run();

      check(box.store).deepEquals({7: 'v'});
      check(facade.keys).deepEquals([7]);
    });

    scenario('a custom codec owns the raw encoding and the decode round-trip', () async {
      final date = DateTime.utc(2026, 7, 21);
      final dateKeyed = lazyKeyedBoxAround<String, DateTime>(
        'logs',
        () async => box,
        codec: const DateKeyCodec(),
      );

      await dateKeyed.put(date, 'v').run();

      check(box.store.keys).deepEquals([date.toIso8601String()]);
      check(dateKeyed.keys).deepEquals([date]);
    });

    scenario('a key type without an identity default and no codec fails the wiring assert', () {
      check(
        () => lazyKeyedBoxAround<String, DateTime>('logs', () async => box),
      ).throws<AssertionError>();
    });
  });

  feature('LazyKeyedBox auto-open', () {
    scenario('construction opens nothing; the first effect opens exactly once', () async {
      check(openCalls).equals(0);

      await facade.put(7, 'v').run();
      await facade.put(8, 'w').run();

      check(openCalls).equals(1);
      check(observer.calls.first).equals('opened:logs');
    });

    scenario('concurrent first effects share one single-flight open', () async {
      final gate = Completer<void>();
      final gatedBox = FakeLazyBox(name: 'logs');
      final gated = lazyKeyedBoxAround<String, int>('logs', () async {
        openCalls++;
        await gate.future;

        return gatedBox;
      });

      final racing = [gated.put(1, 'a').run(), gated.get(1).run(), gated.values.run()];
      check(openCalls).equals(1);

      gate.complete();
      await racing.wait;

      check(openCalls).equals(1);
    });

    scenario('the sync inspectors throw StateError before the first open, then work', () async {
      check(() => facade.length).throws<StateError>();
      check(() => facade.isEmpty).throws<StateError>();
      check(() => facade.isNotEmpty).throws<StateError>();
      check(() => facade.keys).throws<StateError>();
      check(() => facade.contains(7)).throws<StateError>();
      check(facade.name).equals('logs');

      await facade.ensureInitialised().run();
      await facade.put(7, 'v').run();

      check(facade.length).equals(1);
      check(facade.isEmpty).isFalse();
      check(facade.isNotEmpty).isTrue();
      check(facade.keys).deepEquals([7]);
      check(facade.contains(7)).isTrue();
    });

    scenario('a failed open dispatches, resets, and the next run retries', () async {
      var attempts = 0;
      final retrying = lazyKeyedBoxAround<String, int>('logs', () async {
        attempts++;
        if (attempts == 1) throw HiveError('locked');

        return box;
      }, observer: observer);

      await check(retrying.put(7, 'v').run()).throws<HiveError>();
      await retrying.put(7, 'v').run();

      check(attempts).equals(2);
      check(box.store).deepEquals({7: 'v'});
      check(observer.calls).deepEquals([
        'error:logs:open:HiveError',
        'error:logs:put:HiveError',
        'opened:logs',
        'written:logs:7:v',
      ]);
    });
  });

  feature('LazyKeyedBox reads', () {
    scenario('an absent key reads as None and falls back through getOr', () async {
      final result = await facade.get(7).run();

      check(result.isNone()).isTrue();
      check(await facade.getOr(7, 'fallback').run()).equals('fallback');
    });

    scenario('stored entries read back as Some, through getOr, and via values', () async {
      await facade.putAll({1: 'a', 2: 'b'}).run();

      final present = await facade.get(1).run();

      check(present.toNullable()).equals('a');
      check(await facade.getOr(1, 'fallback').run()).equals('a');
      check(await facade.values.run()).deepEquals(['a', 'b']);
    });
  });

  feature('LazyKeyedBox writes', () {
    scenario('the corruption gate throws at the call site, before the box even opens', () {
      check(() => facade.put(-1, 'v')).throws<ArgumentError>();
      check(() => facade.putAll({1: 'a', -1: 'b'})).throws<ArgumentError>();

      check(openCalls).equals(0);
      check(box.store).isEmpty();
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
      ).deepEquals(['deleted:logs:1', 'deleted:logs:2', 'deleted:logs:3', 'cleared:logs']);
    });
  });

  feature('LazyKeyedBox watch', () {
    scenario('writes carry Some, deletes carry None, and deleted derives from it', () async {
      final events = <LazyTypedBoxEvent<String, int>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(7, 'v').run();
      await facade.delete(7).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [
        LazyTypedBoxEvent<String, int>(key: 7, value: Some('v')),
        LazyTypedBoxEvent<String, int>(key: 7, value: None()),
      ]);
      check(events.last.deleted).isTrue();
    });

    scenario('a key filter narrows the stream to that key', () async {
      final events = <LazyTypedBoxEvent<String, int>>[];
      final subscription = facade.watch(key: 2).listen(events.add);
      await pumpEventQueue();

      await facade.putAll({1: 'a', 2: 'b'}).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [LazyTypedBoxEvent<String, int>(key: 2, value: Some('b'))]);
    });
  });

  feature('LazyKeyedBox lifecycle', () {
    scenario('close before first use never opens, yet turns the handle terminal', () async {
      await facade.close().run();

      check(openCalls).equals(0);
      check(observer.calls).deepEquals(['closed:logs']);

      await check(facade.put(7, 'v').run()).throws<HiveError>();
      check(() => facade.length).throws<HiveError>();
    });

    scenario('close after use closes the real box and is terminal (tier 3)', () async {
      await facade.put(7, 'v').run();
      observer.calls.clear();

      await facade.close().run();

      check(box.closed).isTrue();
      await check(facade.get(7).run()).throws<HiveError>();
      check(observer.calls).deepEquals(['closed:logs', 'error:logs:get:HiveError']);
    });

    scenario('flush, compact, and deleteFromDisk delegate to the box', () async {
      await facade.flush().run();
      await facade.compact().run();
      await facade.deleteFromDisk().run();

      check(box.flushCount).equals(1);
      check(box.compactCount).equals(1);
      check(box.deletedFromDisk).isTrue();
    });
  });
}
