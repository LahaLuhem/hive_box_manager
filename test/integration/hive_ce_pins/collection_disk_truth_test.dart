// Pins what hive_ce reads back after a restart, which the value codecs rely on. Same-session reads
// come from the write cache, so every scenario closes and reopens before asserting.
//
// The pinned subject is `dynamic` itself (what hive reifies for collections), so the DCM ban is lifted
// for this file.
// ignore_for_file: avoid-dynamic
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:checks/checks.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/support.dart';

void main() {
  const alice = Person('alice', 30);
  const bob = Person('bob', 40);
  useTempHive('hbm_pins_');

  setUpAll(() => Hive.registerAdapter(const PersonAdapter()));

  Future<Box<Object>> reopen(Box<Object> box) async {
    final boxName = box.name;
    await box.close();

    return await Hive.openBox<Object>(boxName);
  }

  feature('hive_ce disk truth for collections of a custom type', () {
    scenario('same-session reads return the written instance (write cache flatters)', () async {
      final box = await Hive.openBox<Object>('collections');
      const written = [alice, bob];
      await box.put('list', written);

      check(identical(box.get('list'), written)).isTrue();
    });

    scenario('a written List<T> reads back as List<dynamic>, castable at the boundary', () async {
      var box = await Hive.openBox<Object>('collections');
      await box.put('list', <Person>[alice, bob]);
      box = await reopen(box);

      final raw = box.get('list');
      check(raw is List<Person>).isFalse();
      final castView = check(raw).isA<List<dynamic>>();
      castView.length.equals(2);
      check((raw! as List<dynamic>).cast<Person>().first).equals(alice);
    });

    scenario('a written Set<T> survives as Set<dynamic>, castable at the boundary', () async {
      var box = await Hive.openBox<Object>('collections');
      await box.put('set', <Person>{alice});
      box = await reopen(box);

      final raw = box.get('set');
      check(raw is Set<Person>).isFalse();
      check(raw).isA<Set<dynamic>>();
      check((raw! as Set<dynamic>).cast<Person>().contains(alice)).isTrue();
    });

    scenario('a written Map<K, V> reads back as Map<dynamic, dynamic>, castable', () async {
      var box = await Hive.openBox<Object>('collections');
      await box.put('map', <String, Person>{'a': alice});
      box = await reopen(box);

      final raw = box.get('map');
      check(raw is Map<String, Person>).isFalse();
      check(raw).isA<Map<dynamic, dynamic>>();
      check((raw! as Map<dynamic, dynamic>).cast<String, Person>()['a']).equals(alice);
    });

    scenario('opening a typed collection box is refused outright while asserts are on', () async {
      // Future.sync folds the guard's synchronous throw into the checked future.
      await check(Future.sync(() => Hive.openBox<List<Person>>('typed'))).throws<AssertionError>();
      await check(Future.sync(() => Hive.openLazyBox<List<Person>>('typed')))
          .throws<AssertionError>();
    });

    scenario('a dynamic-parameterised lazy box + cast at the read boundary works', () async {
      final box = await Hive.openBox<Object>('castable');
      await box.put('k', <Person>[alice]);
      await box.close();

      final reopened = await Hive.openLazyBox<List<dynamic>>('castable');
      final raw = await reopened.get('k');
      check(raw!.cast<Person>().first).equals(alice);
    });

    scenario('non-List Iterables are rejected by the engine at put', () async {
      final box = await Hive.openBox<Object>('collections');
      final lazyView = <Person>[alice, bob].map((person) => person);

      await check(box.put('iterable', lazyView)).throws<HiveError>();
    });
  });

  feature('stored shapes after a reopen', () {
    scenarioOutline<Future<ShapeVerdicts> Function()>(
      'the wiring check allows exactly the shapes that read back typed',
      examples: storedShapes,
      outline: (verdictsOf) async {
        final verdicts = await verdictsOf();

        check(
          because: 'hive reads it back typed: ${verdicts.readsBackTyped}',
          verdicts.isAllowed,
        ).equals(verdicts.readsBackTyped);
      },
    );
  });

  feature('int keys inside a map after a reopen', () {
    scenario("2 keys a 64-bit float can't tell apart come back as one entry", () async {
      const imprecise = ProbeKeyLimits.firstWebImpreciseInt;
      final neighbour = imprecise.toDouble().toInt();
      var box = await Hive.openBox<Object>('collections');
      await box.put('map', {neighbour: 'first', imprecise: 'second'});
      box = await reopen(box);

      check((box.get('map')! as Map<Object?, Object?>).keys).deepEquals([neighbour]);
    });
  });

  feature('ints in a value after a reopen', () {
    scenarioOutline<Future<IntVerdicts> Function()>(
      'hive keeps an int exactly when a round trip through a double does',
      examples: storedInts,
      outline: (verdictsOf) async {
        final verdicts = await verdictsOf();

        check(verdicts.unchangedIn).deepEquals({
          for (final position in verdicts.unchangedIn.keys) position: verdicts.survivesDouble,
        });
      },
    );
  });

  feature('DateTime and Duration after a reopen', () {
    scenarioOutline<Future<Map<String, bool>> Function()>(
      'hive keeps microseconds inside the range, and whole milliseconds anywhere',
      examples: keptTimes,
      outline: (unchangedInOf) async {
        final unchangedIn = await unchangedInOf();

        check(unchangedIn).deepEquals({for (final position in unchangedIn.keys) position: true});
      },
    );

    scenarioOutline<Future<Map<String, bool>> Function()>(
      'past the range, hive changes the microseconds',
      examples: changedTimes,
      outline: (unchangedInOf) async {
        final unchangedIn = await unchangedInOf();

        check(unchangedIn).deepEquals({for (final position in unchangedIn.keys) position: false});
      },
    );
  });

  feature('the #150 trap with asserts stripped (release truth, via subprocess)', () {
    late Map<String, Object?> verdicts;

    setUpAll(() async => verdicts = await runReleaseModeProbe());

    scenario('the typed box opens fine and throws TypeError only at the first get', () {
      check(verdicts['typedBoxOpenedFine']).equals(true);
      check(verdicts['typedBoxEagerGet']).equals('threw TypeError');
      check(verdicts['typedBoxLazyGet']).equals('threw TypeError');
    });
  });
}
