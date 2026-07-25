// The lazy list façade end to end against real hive_ce on temp dirs, through the public
// barrel: auto-open, the collection disk truth of upstream issue 150 with a custom adapter
// type via a new instance, Option-valued watch payloads, the sugar semantics, and the
// pre-first-use close no-op rider.
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
    tempDir = Directory.systemTemp.createTempSync('hbm_lazy_list_box_');
    Hive
      ..init(tempDir.path)
      ..registerAdapter(PersonAdapter(), override: true);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('LazyListBox against real hive', () {
    scenario('custom-type lists reify typed across close + a new instance', () async {
      const people = [Person('a', 1), Person('b', 2)];
      final first = LazyListBox<Person, int>('people');
      await first.put(1, people).run();
      await first.close().run();

      final second = LazyListBox<Person, int>('people');
      final read = await second.getOr(1).run();

      check(read).deepEquals(people);
      check(read).isA<List<Person>>();
      check(() => read.add(const Person('rogue', 0))).throws<UnsupportedError>();
    });

    scenario('construction touches nothing; inspectors work after the first effect', () async {
      final facade = LazyListBox<String, int>('tags');

      check(Hive.isBoxOpen('tags')).isFalse();
      check(() => facade.length).throws<StateError>();

      await facade.put(1, ['a']).run();

      check(Hive.isBoxOpen('tags')).isTrue();
      check(facade.keys).deepEquals([1]);
      check(facade.contains(1)).isTrue();
    });

    scenario('absent is None, stored-empty is Some(empty), values materialise', () async {
      final facade = LazyListBox<String, int>('tags');

      await facade.put(1, <String>[]).run();
      await facade.put(2, ['b']).run();

      final absent = await facade.get(9).run();
      check(absent.isNone()).isTrue();

      final storedEmpty = await facade.get(1).run();
      check(storedEmpty.toNullable()).isNotNull().deepEquals(<String>[]);

      check(await facade.values.run()).deepEquals([
        <String>[],
        ['b'],
      ]);
    });

    scenario('add, addAll, remove, and update round-trip on the lazy axis', () async {
      final facade = LazyListBox<String, int>('tags');

      await facade.add(1, 'a').run();
      await facade.addAll(1, ['b', 'a']).run();
      await facade.remove(1, 'a').run();

      check(await facade.getOr(1).run()).deepEquals(['b', 'a']);

      check(await facade.update(1, (values) => [...values, 'c']).run()).deepEquals(['b', 'a', 'c']);
      await check(facade.update(9, (values) => values).run()).throws<ArgumentError>();
    });

    scenario('writes carry Some of the view, deletes carry None', () async {
      final facade = LazyListBox<String, int>('tags');
      await facade.ensureInitialised().run();
      final events = <LazyTypedBoxEvent<List<String>, int>>[];
      final subscription = facade.watch().listen(events.add);
      await pumpEventQueue();

      await facade.put(1, ['a']).run();
      await facade.delete(1).run();
      await pumpEventQueue();
      await subscription.cancel();

      check(events).length.equals(2);
      check(events.first.value.toNullable()).isNotNull().deepEquals(['a']);
      check(events.last.deleted).isTrue();
    });

    scenario('close before first use never creates the box, yet is terminal', () async {
      final untouched = LazyListBox<String, int>('never_used');

      await untouched.close().run();

      check(Hive.isBoxOpen('never_used')).isFalse();
      check(File('${tempDir.path}/never_used.hive').existsSync()).isFalse();
      await check(untouched.put(1, ['a']).run()).throws<HiveError>();
    });
  });
}
