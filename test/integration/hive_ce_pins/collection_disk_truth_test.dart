// Pins hive_ce 2.19.3's disk truth for collections of a custom type (probe P3; upstream issue #150):
// what a restart actually reads back, which the 1.0 value-codec design builds on. Same-session cache
// reads flatter the engine, so every disk-truth scenario closes and reopens before asserting. The typed
// collection box guard (typedMapOrIterableCheck) is assert-gated: asserts on (dart test, debug builds)
// refuse the open outright; asserts off (release, probed via subprocess) let it open and blow up at
// the first get, which is the actual #150 trap.
//
// The pinned subject is `dynamic` itself (what hive reifies for collections), so the DCM ban is
// lifted for this file.
// ignore_for_file: avoid-dynamic
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/fixtures/person.dart';
import '../../support/pins/release_probe_runner.dart';

void main() {
  const alice = Person('alice', 30);
  const bob = Person('bob', 40);
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_pins_');
    Hive.init(tempDir.path);
    // Guarded rather than `override: true`: adapters outlive Hive.close(), and re-overriding prints
    // an engine warning into every test's output.
    if (!Hive.isAdapterRegistered(PersonAdapter().typeId)) {
      Hive.registerAdapter(PersonAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<Box<Object>> reopen(Box<Object> box) async {
    final boxName = box.name;
    await box.close();

    return Hive.openBox<Object>(boxName);
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
      await check(
        Future.sync(() => Hive.openLazyBox<List<Person>>('typed')),
      ).throws<AssertionError>();
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

  feature('the #150 trap with asserts stripped (release truth, via subprocess)', () {
    late Directory probeDir;
    late Map<String, Object?> verdicts;

    setUpAll(() async {
      probeDir = Directory.systemTemp.createTempSync('hbm_release_probe_');
      verdicts = await runReleaseModeProbe(probeDir);
    });

    tearDownAll(() => probeDir.deleteSync(recursive: true));

    scenario('the typed box opens fine and throws TypeError only at the first get', () {
      check(verdicts['typedBoxOpenedFine']).equals(true);
      check(verdicts['typedBoxEagerGet']).equals('threw TypeError');
      check(verdicts['typedBoxLazyGet']).equals('threw TypeError');
    });
  });
}
