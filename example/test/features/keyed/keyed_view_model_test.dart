// The keyed demo's behaviour through its view-model, BDD-shaped via bdd_framework against real
// hive on a temp dir. Input values live in the example rows, read back through the context.
import 'dart:io';

import 'package:bdd_framework/bdd_framework.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/keyed/keyed_view_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late KeyedViewModel vm;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_example_keyed_');
    Hive.init(tempDir.path);
    vm = KeyedViewModel();
  });

  tearDown(() async {
    vm.onUnmount();
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  final feature = BddFeature('Keyed demo');

  Bdd(feature)
      .scenario('Adding an entry stores it and refreshes the listing.')
      .given('An open keyed demo box with no entries.')
      .when('The user types a value and presses Add.')
      .then('The listing shows the value under the first key.')
      .example(val('typed value', 'first note'), val('stored key', 1))
      .run((ctx) async {
        final typedValue = ctx.example.val('typed value') as String;
        final storedKey = ctx.example.val('stored key') as int;
        vm.init();
        await vm.ready;

        vm.valueController.text = typedValue;
        await vm.onAddPressed();

        check(vm.entries.value).deepEquals([(storedKey, typedValue)]);
        check(vm.observer.entries.value.any((line) => line.contains('wrote'))).isTrue();
      });

  Bdd(feature)
      .scenario('Deleting an entry removes it from the box and the listing.')
      .given('A keyed demo box holding two entries.')
      .when('The user deletes the first one.')
      .then('Only the second remains.')
      .example(
        val('first value', 'one'),
        val('second value', 'two'),
        val('deleted key', 1),
        val('remaining key', 2),
      )
      .run((ctx) async {
        final firstValue = ctx.example.val('first value') as String;
        final secondValue = ctx.example.val('second value') as String;
        final deletedKey = ctx.example.val('deleted key') as int;
        final remainingKey = ctx.example.val('remaining key') as int;
        vm.init();
        await vm.ready;
        vm.valueController.text = firstValue;
        await vm.onAddPressed();
        vm.valueController.text = secondValue;
        await vm.onAddPressed();

        await vm.onDeletePressed(deletedKey);

        check(vm.entries.value).deepEquals([(remainingKey, secondValue)]);
      });

  Bdd(feature)
      .scenario('Blank input is ignored.')
      .given('An open keyed demo box.')
      .when('The user presses Add with nothing useful typed.')
      .then('Nothing is stored.')
      .example(val('typed value', '   '))
      .example(val('typed value', ''))
      .run((ctx) async {
        final typedValue = ctx.example.val('typed value') as String;
        vm.init();
        await vm.ready;

        vm.valueController.text = typedValue;
        await vm.onAddPressed();

        check(vm.entries.value).isEmpty();
      });
}
