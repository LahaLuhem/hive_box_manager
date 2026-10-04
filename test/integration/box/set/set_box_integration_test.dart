@TestOn('vm')
@Tags(['integration'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  useTempHive('hbm_set_box_');

  setUpAll(() => Hive.registerAdapter(const MemberAdapter()));

  Future<SetBox<Member, int>> openMembers() =>
      SetBox.open<Member, int>('members', idOf: (member) => member.id).run();

  Future<SetBox<Member, int>> reopen(SetBox<Member, int> box) async {
    // Only a reopen reads from disk, which is where hive hands back fresh objects.
    await box.close().run();

    return openMembers();
  }

  feature('SetBox against real hive', () {
    scenario('a set of a custom type reads back typed after a reopen', () async {
      final box = await openMembers();
      await box.put(1, [Member(1, 'a'), Member(2, 'b')]).run();

      final reopened = await reopen(box);

      check(reopened.getOr(1)).isA<Set<Member>>();
      check(reopened.getOr(1).names).deepEquals(['a', 'b']);
    });

    scenario('value-type elements need no idOf and come back typed, in order', () async {
      var box = await SetBox.open<String, int>('tags').run();
      await box.put(1, ['b', 'a', 'b']).run();
      await box.close().run();

      box = await SetBox.open<String, int>('tags').run();

      check(box.getOr(1)).isA<Set<String>>();
      check(box.getOr(1).toList()).deepEquals(['b', 'a']);
    });

    scenario('re-adding a stored id after a reopen keeps the stored element', () async {
      final box = await openMembers();
      await box.put(1, [Member(1, 'stored')]).run();
      final reopened = await reopen(box);

      await reopened.add(1, Member(1, 'again')).run();

      check(reopened.getOr(1).names).deepEquals(['stored']);
    });

    scenario('upsert after a reopen replaces the element where it sits', () async {
      final box = await openMembers();
      await box.put(1, [Member(1, 'a'), Member(2, 'old'), Member(3, 'c')]).run();
      final reopened = await reopen(box);

      await reopened.upsert(1, Member(2, 'new')).run();

      check(reopened.getOr(1).names).deepEquals(['a', 'new', 'c']);
    });

    scenario('remove after a reopen matches a fresh copy by id', () async {
      final box = await openMembers();
      await box.put(1, [Member(1, 'a'), Member(2, 'b')]).run();
      final reopened = await reopen(box);

      await reopened.remove(1, Member(1, 'fresh copy')).run();

      check(reopened.getOr(1).names).deepEquals(['b']);
    });

    scenario('a read answers the same in the session and after a reopen', () async {
      final box = await openMembers();
      await box.put(1, [Member(1, 'a')]).run();
      final inSession = box.getOr(1).contains(Member(1, 'a'));

      final reopened = await reopen(box);

      check(reopened.getOr(1).contains(Member(1, 'a'))).equals(inSession);
    });

    scenario('insertion order survives a reopen', () async {
      final box = await openMembers();
      await box.put(1, [Member(3, 'c'), Member(1, 'a'), Member(2, 'b')]).run();

      final reopened = await reopen(box);

      check(reopened.getOr(1).names).deepEquals(['c', 'a', 'b']);
    });

    scenario('absent stays None and stored-empty stays Some(empty) across a reopen', () async {
      final box = await openMembers();
      await box.put(1, const <Member>[]).run();

      final reopened = await reopen(box);

      check(reopened.get(9).isNone()).isTrue();
      check(reopened.get(1).toNullable()).isNotNull().isEmpty();
    });

    scenario('writes are copied and reads reject mutation, before and after a reopen', () async {
      final source = {Member(1, 'a')};
      final box = await openMembers();
      await box.put(1, source).run();
      source.add(Member(2, 'rogue'));

      check(box.getOr(1).names).deepEquals(['a']);
      check(() => box.getOr(1).add(Member(3, 'rogue'))).throws<UnsupportedError>();

      final reopened = await reopen(box);

      check(() => reopened.getOr(1).add(Member(3, 'rogue'))).throws<UnsupportedError>();
    });

    scenario('a custom element type without idOf fails while wiring', () {
      check(() => SetBox.open<Member, int>('members')).throws<AssertionError>();
    });
  });
}
