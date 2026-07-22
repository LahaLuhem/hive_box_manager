// The eager iterable façade end to end against real hive_ce on temp dirs, through the public
// barrel: the collection disk truth of upstream issue 150 with a custom adapter type, reads
// asserted only after close and reopen, the aliasing pins against hive's real cache,
// absent-vs-empty on disk, the sugar semantics, and the terminal lifecycle.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/fixtures/person.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_iterable_');
    Hive
      ..init(tempDir.path)
      ..registerAdapter(PersonAdapter(), override: true);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('IterableBox disk truth against real hive (the issue-#150 path)', () {
    scenario('custom-type lists reify typed across close + reopen', () async {
      const people = [Person('a', 1), Person('b', 2)];
      var facade = await IterableBox.open<Person, int>('people').run();
      await facade.put(1, people).run();
      await facade.close().run();

      facade = await IterableBox.open<Person, int>('people').run();

      // From disk hive reifies List<dynamic>; the read boundary restores List<Person>.
      check(facade.getOr(1)).deepEquals(people);
      check(facade.getOr(1)).isA<List<Person>>();
    });

    scenario('the post-reopen view still rejects mutation', () async {
      var facade = await IterableBox.open<Person, int>('people').run();
      await facade.put(1, const [Person('a', 1)]).run();
      await facade.close().run();

      facade = await IterableBox.open<Person, int>('people').run();

      check(() => facade.getOr(1).add(const Person('rogue', 0))).throws<UnsupportedError>();
    });

    scenario('absent stays None while stored-empty stays Some(empty) across reopen', () async {
      var facade = await IterableBox.open<Person, int>('people').run();
      await facade.put(1, const <Person>[]).run();
      await facade.close().run();

      facade = await IterableBox.open<Person, int>('people').run();

      check(facade.get(9).isNone()).isTrue();
      check(facade.get(1).toNullable()).isNotNull().deepEquals(const <Person>[]);
    });
  });

  feature("IterableBox aliasing against hive's real cache", () {
    scenario('mutating the source after put never reaches the box', () async {
      final source = [const Person('a', 1)];
      final facade = await IterableBox.open<Person, int>('people').run();

      await facade.put(1, source).run();
      source.add(const Person('rogue', 0));

      check(facade.getOr(1)).deepEquals(const [Person('a', 1)]);
    });

    scenario('same-session reads hand back unmodifiable views over the cache', () async {
      final facade = await IterableBox.open<Person, int>('people').run();
      await facade.put(1, const [Person('a', 1)]).run();

      check(() => facade.getOr(1).add(const Person('rogue', 0))).throws<UnsupportedError>();
    });

    scenario('a lazily-mapped iterable stores fine (materialised before hive)', () async {
      final facade = await IterableBox.open<Person, int>('people').run();

      await facade.put(1, ['a', 'b'].map((name) => Person(name, 1))).run();

      check(facade.getOr(1)).deepEquals(const [Person('a', 1), Person('b', 1)]);
    });
  });

  feature('IterableBox sugar against real hive', () {
    scenario('add, addAll, and remove round-trip with List semantics', () async {
      final facade = await IterableBox.open<String, int>('tags').run();

      await facade.add(1, 'a').run();
      await facade.addAll(1, ['b', 'a']).run();
      check(facade.getOr(1)).deepEquals(['a', 'b', 'a']);

      await facade.remove(1, 'a').run();
      check(facade.getOr(1)).deepEquals(['b', 'a']);

      await facade.remove(1, 'b').run();
      await facade.remove(1, 'a').run();
      check(facade.get(1).toNullable()).isNotNull().deepEquals(<String>[]);

      await facade.remove(9, 'a').run();
      check(facade.get(9).isNone()).isTrue();
    });

    scenario('update seeds, rewrites, and mirrors Map.update on absence', () async {
      final facade = await IterableBox.open<String, int>('tags').run();

      check(
        await facade.update(1, (values) => values, ifAbsent: () => ['seed']).run(),
      ).deepEquals(['seed']);
      check(await facade.update(1, (values) => [...values, 'b']).run()).deepEquals(['seed', 'b']);
      await check(facade.update(9, (values) => values).run()).throws<ArgumentError>();
    });
  });

  feature('IterableBox lifecycle against real hive', () {
    scenario('keys decode, putAll batches, deletes and clear behave keyed', () async {
      final facade = await IterableBox.open<String, int>('tags').run();

      await facade.putAll({
        1: ['a'],
        2: ['b'],
      }).run();

      check(facade.keys).deepEquals([1, 2]);
      check(facade.length).equals(2);

      await facade.delete(1).run();
      await facade.clear().run();

      check(facade.isEmpty).isTrue();
    });

    scenario('close is terminal; deleteFromDisk removes the box file', () async {
      final facade = await IterableBox.open<String, int>('doomed').run();
      await facade.put(1, ['a']).run();
      await facade.flush().run();
      final boxFile = File('${tempDir.path}/doomed.hive');
      check(boxFile.existsSync()).isTrue();

      await facade.deleteFromDisk().run();

      check(boxFile.existsSync()).isFalse();
      check(() => facade.get(1)).throws<HiveError>();
    });
  });
}
