@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:collection';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  const ada = Person('ada', 36);
  const olderAda = Person('ada', 37);
  const bob = Person('bob', 40);
  const cy = Person('cy', 20);
  useTempHive('hbm_map_box_');

  setUpAll(
    () => Hive
      ..registerAdapter(const PersonAdapter())
      ..registerAdapter(const ColourAdapter()),
  );

  Future<MapBox<String, Person, int>> openPeople() =>
      MapBox.open<String, Person, int>('people').run();

  Future<MapBox<String, Person, int>> reopen(MapBox<String, Person, int> box) async {
    // Only a reopen reads from disk, which is where hive hands back an untyped map.
    await box.close().run();

    return await openPeople();
  }

  /// Stores one entry under [entryKey], reopens, and looks it up again the way an app would after a
  /// restart.
  Future<String?> lookUpAfterReopen<MK extends Object>(MK entryKey) async {
    final box = await MapBox.open<MK, String, int>('by_key_type').run();
    await box.put(1, {entryKey: 'found'}).run();
    await box.close().run();

    final reopened = await MapBox.open<MK, String, int>('by_key_type').run();

    return reopened.getOr(1)[entryKey];
  }

  feature('MapBox against real hive', () {
    scenario('a map of a custom value type reads back typed after a reopen', () async {
      final box = await openPeople();
      await box.put(1, {'ada': ada, 'bob': bob}).run();

      final reopened = await reopen(box);

      check(reopened.getOr(1)).isA<Map<String, Person>>();
      check(reopened.getOr(1)).deepEquals({'ada': ada, 'bob': bob});
    });

    scenarioOutline<Future<String?> Function()>(
      'every inner key type the wiring allows still finds its entry after a reopen',
      examples: {
        'String': () => lookUpAfterReopen('ada'),
        'int': () => lookUpAfterReopen(7),
        'double': () => lookUpAfterReopen(1.5),
        'bool': () => lookUpAfterReopen(true),
        'an enum': () => lookUpAfterReopen(Colour.red),
      },
      outline: (lookUp) async => check(await lookUp()).equals('found'),
    );

    scenario('insertion order survives a reopen', () async {
      final box = await openPeople();
      await box.put(1, {'cy': cy, 'ada': ada, 'bob': bob}).run();

      final reopened = await reopen(box);

      check(reopened.getOr(1).keys).deepEquals(['cy', 'ada', 'bob']);
    });

    scenario('addAll and remove after a reopen work on the map read from disk', () async {
      final box = await openPeople();
      await box.put(1, {'ada': ada, 'bob': bob}).run();
      final reopened = await reopen(box);

      await reopened.addAll(1, {'ada': olderAda, 'cy': cy}).run();
      await reopened.remove(1, 'bob').run();

      check(reopened.getOr(1).keys).deepEquals(['ada', 'cy']);
      check(reopened.getOr(1)['ada']).equals(olderAda);
    });

    scenario('a read answers the same in the session and after a reopen', () async {
      final caseInsensitive = LinkedHashMap<String, Person>(
        equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
        hashCode: (key) => key.toLowerCase().hashCode,
      )..['Ada'] = ada;
      final box = await openPeople();
      await box.put(1, caseInsensitive).run();
      final inSession = box.getOr(1).containsKey('ADA');

      final reopened = await reopen(box);

      check(reopened.getOr(1).containsKey('ADA')).equals(inSession);
    });

    scenario('absent stays None and stored-empty stays Some(empty) across a reopen', () async {
      final box = await openPeople();
      await box.put(1, const {}).run();

      final reopened = await reopen(box);

      check(reopened.get(9).isNone()).isTrue();
      check(reopened.get(1).toNullable()).isNotNull().isEmpty();
    });

    scenario('writes are copied and reads reject mutation, before and after a reopen', () async {
      final source = {'ada': ada};
      final box = await openPeople();
      await box.put(1, source).run();
      source['rogue'] = bob;

      check(box.getOr(1).keys).deepEquals(['ada']);
      check(() => box.getOr(1)['rogue'] = bob).throws<UnsupportedError>();

      final reopened = await reopen(box);

      check(() => reopened.getOr(1)['rogue'] = bob).throws<UnsupportedError>();
    });
  });
}
