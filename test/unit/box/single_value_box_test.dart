// The eager single-value façade against the stateful in-memory fake, wired through the
// same-library testing seam: the slot-0 compatibility pin, absence + presence reads, the
// Map.update mirror, clear as the one unset, the Option-mapped watch stream, and terminal
// lifecycle.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/src/box/single_value_box.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/fake_boxes.dart';
import '../../support/recording_box_observer.dart';

void main() {
  late FakeEagerBox box;
  late RecordingBoxObserver observer;
  late SingleValueBox<String> facade;

  setUp(() {
    box = FakeEagerBox(name: 'config');
    observer = RecordingBoxObserver();
    facade = singleValueBoxAround(box, observer: observer);
  });

  feature('SingleValueBox slot compatibility', () {
    scenario('the value is stored under raw slot key 0 (0.0.x boxes read in place)', () async {
      await facade.set('v').run();

      check(box.store).deepEquals({0: 'v'});
    });
  });

  feature('SingleValueBox reads', () {
    scenario('an unset box reads None, falls back through getOr, and counts as empty', () {
      check(facade.get().isNone()).isTrue();
      check(facade.getOr('fallback')).equals('fallback');
      check(facade.length).equals(0);
      check(facade.isEmpty).isTrue();
      check(facade.isNotEmpty).isFalse();
      check(facade.name).equals('config');
    });

    scenario('a set value reads back Some and counts as one entry', () async {
      await facade.set('v').run();

      check(facade.get().toNullable()).equals('v');
      check(facade.getOr('fallback')).equals('v');
      check(facade.length).equals(1);
      check(facade.isNotEmpty).isTrue();
    });
  });

  feature('SingleValueBox writes', () {
    scenario('a set Task is lazy and replaces the previous value', () async {
      final write = facade.set('first');

      check(box.store).isEmpty();

      await write.run();
      await facade.set('second').run();

      check(box.store).deepEquals({0: 'second'});
      check(facade.length).equals(1);
    });

    scenario('update rewrites, seeds via ifAbsent, and mirrors Map.update on absence', () async {
      await check(facade.update((value) => value).run()).throws<ArgumentError>();

      check(await facade.update((value) => value, ifAbsent: () => 'seed').run()).equals('seed');
      check(await facade.update((value) => '$value!').run()).equals('seed!');
    });

    scenario('clear unsets the value and dispatches a clear', () async {
      await facade.set('v').run();
      observer.calls.clear();

      await facade.clear().run();

      check(observer.calls).deepEquals(['cleared:config']);
      check(facade.get().isNone()).isTrue();
    });
  });

  feature('SingleValueBox watch', () {
    scenario('sets stream Some, clears stream None', () async {
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

  feature('SingleValueBox lifecycle and failure paths', () {
    scenario('flush and compact delegate to the box', () async {
      await facade.flush().run();
      await facade.compact().run();

      check(box.flushCount).equals(1);
      check(box.compactCount).equals(1);
    });

    scenario('close is terminal: sync reads and later effects surface hive errors', () async {
      await facade.set('v').run();
      observer.calls.clear();

      await facade.close().run();

      check(() => facade.get()).throws<HiveError>();
      await check(facade.set('w').run()).throws<HiveError>();
      check(observer.calls).deepEquals(['closed:config', 'error:config:put:HiveError']);
    });

    scenario('deleteFromDisk is terminal and reaches storage', () async {
      await facade.set('v').run();

      await facade.deleteFromDisk().run();

      check(box.deletedFromDisk).isTrue();
      check(box.store).isEmpty();
    });
  });
}
