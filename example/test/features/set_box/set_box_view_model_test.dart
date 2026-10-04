// The set-box demo through its view-model: tags that ignore case, written by add or upsert, against
// real hive on a temp dir.
import 'dart:io';

import 'package:bdd_framework/bdd_framework.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/set_box/set_box_view_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late SetBoxViewModel sut;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_example_set_box_');
    Hive.init(tempDir.path);
    sut = SetBoxViewModel()..init();
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

  final feature = BddFeature('SetBox demo');

  Bdd(feature)
      .scenario('A tag in another spelling is the same tag.')
      .given('A set holding a tag in one spelling.')
      .when('The user writes it in another spelling, by add or by upsert.')
      .then('Add keeps the stored spelling, and upsert swaps in the new one where the old one sat.')
      .example(
        val('seeded', ['dart', 'Flutter', 'hive']),
        val('write', 'add'),
        val('typed', 'FLUTTER'),
        val('listed', ['dart', 'Flutter', 'hive']),
      )
      .example(
        val('seeded', ['dart', 'Flutter', 'hive']),
        val('write', 'upsert'),
        val('typed', 'FLUTTER'),
        val('listed', ['dart', 'FLUTTER', 'hive']),
      )
      .run((ctx) async {
        final seeded = ctx.example.val('seeded') as List<String>;
        final write = ctx.example.val('write') as String;
        final typed = ctx.example.val('typed') as String;
        final listed = ctx.example.val('listed') as List<String>;
        await sut.ready;
        await addAll(seeded);

        sut.tagController.text = typed;
        await (write == 'add' ? sut.onAddPressed() : sut.onUpsertPressed());

        check(sut.tags.value).deepEquals(listed);
      });

  Bdd(feature)
      .scenario('Removing a tag takes it out of the set.')
      .given('A set holding 2 tags.')
      .when('The user removes one of them.')
      .then('Only the other one is left.')
      .example(val('seeded', ['dart', 'Flutter']), val('removed', 'Flutter'), val('left', ['dart']))
      .run((ctx) async {
        final seeded = ctx.example.val('seeded') as List<String>;
        final removed = ctx.example.val('removed') as String;
        final left = ctx.example.val('left') as List<String>;
        await sut.ready;
        await addAll(seeded);

        await sut.onRemovePressed(removed);

        check(sut.tags.value).deepEquals(left);
      });
}
