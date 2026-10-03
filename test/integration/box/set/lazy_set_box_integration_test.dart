@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/fixtures/member.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_lazy_set_box_');
    Hive.init(tempDir.path);
    // Adapters outlive Hive.close(), and registering one twice prints a warning.
    if (!Hive.isAdapterRegistered(MemberAdapter().typeId)) Hive.registerAdapter(MemberAdapter());
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  LazySetBox<Member, int> members() =>
      LazySetBox<Member, int>('members', idOf: (member) => member.id);

  Future<Iterable<String>> namesUnder(LazySetBox<Member, int> box, int key) async =>
      (await box.getOr(key).run()).map((member) => member.name);

  feature('LazySetBox against real hive', () {
    scenario('a set of a custom type reads back typed in a new instance', () async {
      final first = members();
      await first.put(1, [Member(1, 'a'), Member(2, 'b')]).run();
      await first.close().run();

      final read = await members().getOr(1).run();

      check(read).isA<Set<Member>>();
      check(read.map((member) => member.name)).deepEquals(['a', 'b']);
      check(() => read.add(Member(3, 'rogue'))).throws<UnsupportedError>();
    });

    scenario('construction touches nothing, and inspectors work after the first effect', () async {
      final box = members();

      check(Hive.isBoxOpen('members')).isFalse();
      check(() => box.length).throws<StateError>();

      await box.put(1, [Member(1, 'a')]).run();

      check(Hive.isBoxOpen('members')).isTrue();
      check(box.keys).deepEquals([1]);
    });

    scenario('re-adding a stored id in the same session keeps the stored element', () async {
      final box = members();
      await box.put(1, [Member(1, 'stored')]).run();

      await box.add(1, Member(1, 'again')).run();

      check(await namesUnder(box, 1)).deepEquals(['stored']);
    });

    scenario('upsert in a new instance replaces the element where it sits', () async {
      final first = members();
      await first.put(1, [Member(1, 'a'), Member(2, 'old'), Member(3, 'c')]).run();
      await first.close().run();

      final second = members();
      await second.upsert(1, Member(2, 'new')).run();

      check(await namesUnder(second, 1)).deepEquals(['a', 'new', 'c']);
    });

    scenario('remove matches a fresh copy by id', () async {
      final box = members();
      await box.put(1, [Member(1, 'a'), Member(2, 'b')]).run();

      await box.remove(1, Member(1, 'fresh copy')).run();

      check(await namesUnder(box, 1)).deepEquals(['b']);
    });

    scenario('insertion order survives, and absent stays apart from stored-empty', () async {
      final first = members();
      await first.putAll({
        1: [Member(3, 'c'), Member(1, 'a'), Member(2, 'b')],
        2: const <Member>[],
      }).run();
      await first.close().run();

      final second = members();

      check(await namesUnder(second, 1)).deepEquals(['c', 'a', 'b']);
      check((await second.get(2).run()).toNullable()).isNotNull().isEmpty();
      check((await second.get(9).run()).isNone()).isTrue();
    });

    scenario('a custom element type without idOf fails while wiring', () {
      check(() => LazySetBox<Member, int>('members')).throws<AssertionError>();
    });
  });
}
