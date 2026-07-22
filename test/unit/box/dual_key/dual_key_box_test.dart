// The eager dual-key façade against the stateful in-memory fake, wired through the
// same-library testing seam: codec defaulting with the packed opt-in included, record
// round-trips, the folded scan queries returning plain lists that track live state, part-domain
// asserts, and terminal lifecycle.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/dual_key/dual_key_box.dart';
import 'package:hive_box_manager/src/codec/dual/packed_int_dual_codec.dart';
import 'package:hive_box_manager/src/event/typed_box_event.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/codecs/date_int_dual_codec.dart';
import '../../../support/doubles/fake_boxes.dart';
import '../../../support/doubles/recording_box_observer.dart';

void main() {
  late FakeEagerBox box;
  late RecordingBoxObserver observer;
  late DualKeyBox<String, int, int> facade;

  setUp(() {
    box = FakeEagerBox(name: 'grid');
    observer = RecordingBoxObserver();
    facade = dualKeyBoxAround(box, observer: observer);
  });

  feature('DualKeyBox wiring and codec defaulting', () {
    scenario('(int, int) parts default to the String composite raw shape', () async {
      await facade.put(7, 9, 'v').run();

      check(box.store).deepEquals({'7:9': 'v'});
      check(facade.keys).deepEquals([(7, 9)]);
    });

    scenario('the packed opt-in stores u32 ints, bit-identical to 0.0.x bitShift', () async {
      final packed = dualKeyBoxAround<String, int, int>(
        FakeEagerBox(),
        codec: const PackedIntDualCodec(),
      );

      await packed.put(7, 9, 'v').run();

      check(packed.get(7, 9).toNullable()).equals('v');
      check(packed.keys).deepEquals([(7, 9)]);
    });

    scenario('the packed codec asserts part domains at the call site', () {
      final packed = dualKeyBoxAround<String, int, int>(
        FakeEagerBox(),
        codec: const PackedIntDualCodec(),
      );

      check(() => packed.put(PackedIntDualCodec.partCeiling, 0, 'v')).throws<AssertionError>();
      check(() => packed.put(0, -1, 'v')).throws<AssertionError>();
    });

    scenario('a custom codec owns the raw encoding and the decode round-trip', () async {
      final date = DateTime.utc(2026, 7, 21);
      final dated = dualKeyBoxAround<String, DateTime, int>(box, codec: const DateIntDualCodec());

      await dated.put(date, 3, 'v').run();

      check(box.store.keys).deepEquals(['${date.toIso8601String()}|3']);
      check(dated.keys).deepEquals([(date, 3)]);
      check(dated.get(date, 3).toNullable()).equals('v');
    });

    scenario('non-(int, int) parts without a codec fail the wiring assert', () {
      check(() => dualKeyBoxAround<String, DateTime, int>(box)).throws<AssertionError>();
    });
  });

  feature('DualKeyBox reads', () {
    scenario('absent composite keys read as None, fall back, and are not contained', () {
      check(facade.get(1, 2).isNone()).isTrue();
      check(facade.getOr(1, 2, 'fallback')).equals('fallback');
      check(facade.contains(1, 2)).isFalse();
    });

    scenario('stored entries surface through every inspector, decoded to records', () async {
      await facade.putAll({(1, 1): 'a', (2, 2): 'b'}).run();

      check(facade.get(1, 1).toNullable()).equals('a');
      check(facade.getOr(1, 1, 'fallback')).equals('a');
      check(facade.contains(2, 2)).isTrue();
      check(facade.keys).deepEquals([(1, 1), (2, 2)]);
      check(facade.values).deepEquals(['a', 'b']);
      check(facade.length).equals(2);
      check(facade.isNotEmpty).isTrue();
      check(facade.name).equals('grid');
    });
  });

  feature('DualKeyBox folded queries', () {
    scenario('no matches is a plain empty list, never None', () {
      final matches = facade.queryByPrimary(42);

      check(matches).isA<List<String>>();
      check(matches).isEmpty();
      check(facade.queryBySecondary(42)).isEmpty();
    });

    scenario('queries collect every match by the requested part', () async {
      await facade.putAll({(1, 1): 'a', (1, 2): 'b', (2, 1): 'c'}).run();

      check(facade.queryByPrimary(1)).deepEquals(['a', 'b']);
      check(facade.queryByPrimary(2)).deepEquals(['c']);
      check(facade.queryBySecondary(1)).deepEquals(['a', 'c']);
      check(facade.queryBySecondary(2)).deepEquals(['b']);
    });

    scenario('queries scan the live key set: deletes shrink the answer', () async {
      await facade.putAll({(1, 1): 'a', (1, 2): 'b'}).run();

      await facade.delete(1, 1).run();

      check(facade.queryByPrimary(1)).deepEquals(['b']);
    });

    scenario('a query dispatches one read per matched key', () async {
      await facade.putAll({(1, 1): 'a', (1, 2): 'b', (2, 1): 'c'}).run();
      observer.calls.clear();

      check(facade.queryByPrimary(1)).deepEquals(['a', 'b']);
      check(observer.calls).deepEquals(['read:grid:(1, 1):a', 'read:grid:(1, 2):b']);
    });
  });

  feature('DualKeyBox writes', () {
    scenario('update rewrites, seeds via ifAbsent, and mirrors Map.update on absence', () async {
      await facade.put(1, 1, 'v').run();

      check(await facade.update(1, 1, (value) => '$value!').run()).equals('v!');
      check(
        await facade.update(9, 9, (value) => value, ifAbsent: () => 'seed').run(),
      ).equals('seed');
      await check(facade.update(8, 8, (value) => value).run()).throws<ArgumentError>();
    });

    scenario('delete, deleteAll, and clear remove entries with per-key dispatch', () async {
      await facade.putAll({(1, 1): 'a', (2, 2): 'b', (3, 3): 'c', (4, 4): 'd'}).run();
      observer.calls.clear();

      await facade.delete(1, 1).run();
      await facade.deleteAll([(2, 2), (3, 3)]).run();
      await facade.clear().run();

      check(box.store).isEmpty();
      check(observer.calls).deepEquals([
        'deleted:grid:(1, 1)',
        'deleted:grid:(2, 2)',
        'deleted:grid:(3, 3)',
        'cleared:grid',
      ]);
    });
  });

  feature('DualKeyBox watch', () {
    scenario('events carry record keys and deletes still carry the value', () async {
      final events = <TypedBoxEvent<String, (int, int)>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(1, 2, 'v').run();
      await facade.delete(1, 2).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [
        TypedBoxEvent<String, (int, int)>(key: (1, 2), value: 'v', deleted: false),
        TypedBoxEvent<String, (int, int)>(key: (1, 2), value: 'v', deleted: true),
      ]);
    });

    scenario('a record filter narrows the stream to that composite key', () async {
      final events = <TypedBoxEvent<String, (int, int)>>[];
      final subscription = facade.watch(key: (2, 2)).listen(events.add);
      await pumpEventQueue();

      await facade.putAll({(1, 1): 'a', (2, 2): 'b'}).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).deepEquals(const [
        TypedBoxEvent<String, (int, int)>(key: (2, 2), value: 'b', deleted: false),
      ]);
    });
  });

  feature('DualKeyBox lifecycle', () {
    scenario('flush and compact delegate; close is terminal', () async {
      await facade.put(1, 1, 'v').run();
      await facade.flush().run();
      await facade.compact().run();

      check(box.flushCount).equals(1);
      check(box.compactCount).equals(1);

      await facade.close().run();

      check(() => facade.get(1, 1)).throws<HiveError>();
      await check(facade.put(1, 2, 'w').run()).throws<HiveError>();
    });

    scenario('deleteFromDisk is terminal and reaches storage', () async {
      await facade.put(1, 1, 'v').run();

      await facade.deleteFromDisk().run();

      check(box.wasDeletedFromDisk).isTrue();
      check(box.store).isEmpty();
    });
  });
}
