// The list-box demo's behaviour through its view-model: the add / remove sugar with List
// semantics per selected key, against real hive on a temp dir. Input values live in the example
// rows, read back through the context.
import 'dart:io';

import 'package:bdd_framework/bdd_framework.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/list_box/list_box_view_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late ListBoxViewModel sut;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_example_list_box_');
    Hive.init(tempDir.path);
    sut = ListBoxViewModel();
  });

  tearDown(() async {
    sut.onUnmount();
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> addAll(List<String> tags) async {
    for (final tag in tags) {
      sut.tagController.text = tag;
      await sut.onAddPressed();
    }
  }

  final feature = BddFeature('ListBox demo');

  Bdd(feature)
      .scenario('Tags accumulate per key, duplicates allowed.')
      .given('An open tags box on the first list.')
      .when('The user adds tags, one of them twice.')
      .then('The listing shows every addition in insertion order.')
      .example(val('added', ['flutter', 'dart', 'flutter']))
      .run((ctx) async {
        final added = ctx.example.val('added') as List<String>;
        sut.init();
        await sut.ready;

        await addAll(added);

        check(sut.tags.value).deepEquals(added);
      });

  Bdd(feature)
      .scenario('Removing a tag drops only its first occurrence.')
      .given('A list seeded with a duplicate tag.')
      .when('The user removes that tag once.')
      .then('Only the first occurrence goes.')
      .example(
        val('seeded', ['flutter', 'dart', 'flutter']),
        val('removed', 'flutter'),
        val('remaining', ['dart', 'flutter']),
      )
      .run((ctx) async {
        final seeded = ctx.example.val('seeded') as List<String>;
        final removed = ctx.example.val('removed') as String;
        final remaining = ctx.example.val('remaining') as List<String>;
        sut.init();
        await sut.ready;
        await addAll(seeded);

        await sut.onRemovePressed(removed);

        check(sut.tags.value).deepEquals(remaining);
      });

  Bdd(feature)
      .scenario('Each key holds its own list.')
      .given('A tag stored under the first list.')
      .when('The user switches to another list and back.')
      .then('The other list is empty and the first is intact.')
      .example(val('tag', 'only-on-1'), val('other list', 2), val('home list', 1))
      .run((ctx) async {
        final tag = ctx.example.val('tag') as String;
        final otherList = ctx.example.val('other list') as int;
        final homeList = ctx.example.val('home list') as int;
        sut.init();
        await sut.ready;
        await addAll([tag]);

        sut.onKeySelected(otherList);
        check(sut.tags.value).isEmpty();

        sut.onKeySelected(homeList);
        check(sut.tags.value).deepEquals([tag]);
      });
}
