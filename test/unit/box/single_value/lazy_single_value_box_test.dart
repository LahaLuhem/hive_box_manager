// The lazy single-value façade against the stateful in-memory fake, wired through the
// same-library testing seam: single-flight auto-open, the sync-inspector carve-out, the slot-0
// pin, TaskOption reads, the Option watch stream on the lazy axis, and the pre-first-use close
// no-op rider.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/src/box/single_value/lazy_single_value_box.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/doubles/fake_boxes.dart';
import '../../../support/doubles/recording_box_observer.dart';

void main() {
  late FakeLazyBox box;
  late RecordingBoxObserver observer;
  late int openCalls;
  late LazySingleValueBox<String> facade;

  setUp(() {
    box = FakeLazyBox(name: 'config');
    observer = RecordingBoxObserver();
    openCalls = 0;
    facade = lazySingleValueBoxAround('config', () async {
      openCalls++;

      return box;
    }, observer: observer);
  });

  feature('LazySingleValueBox auto-open and slot compatibility', () {
    scenario('construction opens nothing; the first effect opens once and hits slot 0', () async {
      check(openCalls).equals(0);

      await facade.set('v').run();

      check(openCalls).equals(1);
      check(box.store).deepEquals({0: 'v'});
      check(observer.calls.first).equals('opened:config');
    });

    scenario('the sync inspectors throw StateError before the first open, then work', () async {
      check(() => facade.length).throws<StateError>();
      check(() => facade.isEmpty).throws<StateError>();
      check(() => facade.isNotEmpty).throws<StateError>();
      check(facade.name).equals('config');

      await facade.ensureInitialised().run();

      check(facade.length).equals(0);
      check(facade.isEmpty).isTrue();
    });
  });

  feature('LazySingleValueBox reads and writes', () {
    scenario('an unset box reads None and falls back through getOr', () async {
      final result = await facade.get().run();

      check(result.isNone()).isTrue();
      check(await facade.getOr('fallback').run()).equals('fallback');
    });

    scenario('a set value reads back Some and through getOr', () async {
      await facade.set('v').run();

      final result = await facade.get().run();

      check(result.toNullable()).equals('v');
      check(await facade.getOr('fallback').run()).equals('v');
    });

    scenario('update rewrites, seeds via ifAbsent, and mirrors Map.update on absence', () async {
      await check(facade.update((value) => value).run()).throws<ArgumentError>();

      check(await facade.update((value) => value, ifAbsent: () => 'seed').run()).equals('seed');
      check(await facade.update((value) => '$value!').run()).equals('seed!');
    });

    scenario('clear unsets the value', () async {
      await facade.set('v').run();

      await facade.clear().run();

      final result = await facade.get().run();
      check(result.isNone()).isTrue();
    });
  });

  feature('LazySingleValueBox watch', () {
    scenario('sets stream Some, clears stream None (lazy deletes carry no value)', () async {
      final events = <Option<String>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.set('v').run();
      await facade.clear().run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [Some('v'), None()]);
    });
  });

  feature('LazySingleValueBox lifecycle', () {
    scenario('close before first use never opens, yet turns the handle terminal', () async {
      await facade.close().run();

      check(openCalls).equals(0);
      check(observer.calls).deepEquals(['closed:config']);
      await check(facade.set('v').run()).throws<HiveError>();
    });

    scenario('flush, compact, and deleteFromDisk delegate to the box', () async {
      await facade.flush().run();
      await facade.compact().run();
      await facade.deleteFromDisk().run();

      check(box.flushCount).equals(1);
      check(box.compactCount).equals(1);
      check(box.wasDeletedFromDisk).isTrue();
    });
  });
}
