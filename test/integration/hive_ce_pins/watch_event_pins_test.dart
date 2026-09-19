// Pins what hive_ce puts in a watch event. Eager events always carry the value, deletes and clears included,
// while lazy ones carry null because a LazyBox keeps nothing in memory.
//
// That split is what [TypedBoxEvent] and [LazyTypedBoxEvent] are built on, so an engine upgrade that
// starts delivering lazy delete values fails here loudly rather than quietly widening the contract.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

/// Collects what [stream] emits while [act] runs, draining the queue first so nothing in flight gets
/// missed.
Future<List<BoxEvent>> record(Stream<BoxEvent> stream, Future<void> Function() act) async {
  final events = <BoxEvent>[];
  final subscription = stream.listen(events.add);
  await act();
  await pumpEventQueue();
  await subscription.cancel();

  return events;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_pins_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('hive_ce watch-event payloads, eager axis', () {
    scenario('a delete event carries the latest stored value, not null', () async {
      final box = await Hive.openBox<String>('watched');
      final events = await record(box.watch(), () async {
        await box.put('k', 'v1');
        await box.put('k', 'v2');
        await box.delete('k');
      });

      check(events).length.equals(3);
      final deleteEvent = events.last;
      check(deleteEvent.deleted).isTrue();
      check(deleteEvent.value).equals('v2');
    });

    scenario('clear() emits one per-key delete event, each carrying its value', () async {
      final box = await Hive.openBox<String>('watched');
      await box.put('a', '1');
      await box.put('b', '2');
      final events = await record(box.watch(), box.clear);

      check(events).length.equals(2);
      check(events.map((event) => event.deleted).toSet()).deepEquals({true});
      check(events.map((event) => event.value)).deepEquals(['1', '2']);
    });
  });

  feature('hive_ce watch-event payloads, lazy axis', () {
    scenario('put events carry the value; the delete event carries null', () async {
      final box = await Hive.openLazyBox<String>('lazy_watched');
      final events = await record(box.watch(), () async {
        await box.put('k', 'stored-value');
        await box.delete('k');
      });

      check(events).length.equals(2);
      check(events.first.deleted).isFalse();
      check(events.first.value).equals('stored-value');
      check(events.last.deleted).isTrue();
      check(events.last.value).isNull();
    });

    scenario('the delete event stays null after a reopen (disk truth)', () async {
      var box = await Hive.openLazyBox<String>('lazy_watched');
      await box.put('k', 'stored-value');
      await box.close();

      box = await Hive.openLazyBox<String>('lazy_watched');
      final events = await record(box.watch(), () => box.delete('k'));

      check(events).length.equals(1);
      check(events.single.deleted).isTrue();
      check(events.single.value).isNull();
    });

    scenario('clear() emits per-key delete events, each carrying null', () async {
      final box = await Hive.openLazyBox<String>('lazy_watched');
      await box.put('a', '1');
      await box.put('b', '2');
      final events = await record(box.watch(), box.clear);

      check(events).length.equals(2);
      check(events.map((event) => event.deleted).toSet()).deepEquals({true});
      check(events.map((event) => event.value)).deepEquals([null, null]);
    });
  });
}
