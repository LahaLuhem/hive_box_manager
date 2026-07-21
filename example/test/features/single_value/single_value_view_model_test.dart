// The encrypted single-value demo's behaviour through its view-model: the current value is fed
// by the box's watch stream, so every assertion drains the event queue first. Input values live
// in the example rows, read back through the context.
import 'dart:io';

import 'package:bdd_framework/bdd_framework.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/single_value/single_value_view_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late SingleValueViewModel vm;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_example_single_');
    Hive.init(tempDir.path);
    vm = SingleValueViewModel();
  });

  tearDown(() async {
    vm.onUnmount();
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  final feature = BddFeature('Encrypted single-value demo');

  Bdd(feature)
      .scenario('Saving a token surfaces it through the watch stream.')
      .given('An encrypted single-value box with nothing stored.')
      .when('The user types a token and saves it.')
      .then('The current value becomes Some of that token.')
      .example(val('token', 'secret-123'))
      .example(val('token', 'påss wörd 🔑'))
      .run((ctx) async {
        final token = ctx.example.val('token') as String;
        vm.init();

        vm.tokenController.text = token;
        await vm.onSavePressed();
        await pumpEventQueue();

        check(vm.current.value.toNullable()).equals(token);
      });

  Bdd(feature)
      .scenario('Clearing unsets the value.')
      .given('A stored token.')
      .when('The user presses Clear.')
      .then('The current value becomes None again.')
      .example(val('token', 'secret-123'))
      .run((ctx) async {
        final token = ctx.example.val('token') as String;
        vm.init();
        vm.tokenController.text = token;
        await vm.onSavePressed();
        await pumpEventQueue();

        await vm.onClearPressed();
        await pumpEventQueue();

        check(vm.current.value.isNone()).isTrue();
      });
}
