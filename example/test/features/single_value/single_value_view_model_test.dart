// The encrypted single-value demo through its view-model. The watch stream feeds the current value,
// so every assertion drains the event queue first.

import 'package:bdd_framework/bdd_framework.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/single_value/single_value_view_model.dart';

import '../../support/temp_hive.dart';

void main() {
  useTempHive('hbm_example_single_');
  late SingleValueViewModel sut;

  setUp(() {
    sut = SingleValueViewModel();
  });

  tearDown(() => sut.onUnmount());

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
        sut.init();

        sut.tokenController.text = token;
        await sut.onSavePressed();
        await pumpEventQueue();

        check(sut.current.value.toNullable()).equals(token);
      });

  Bdd(feature)
      .scenario('Clearing unsets the value.')
      .given('A stored token.')
      .when('The user presses Clear.')
      .then('The current value becomes None again.')
      .example(val('token', 'secret-123'))
      .run((ctx) async {
        final token = ctx.example.val('token') as String;
        sut.init();
        sut.tokenController.text = token;
        await sut.onSavePressed();
        await pumpEventQueue();

        await sut.onClearPressed();
        await pumpEventQueue();

        check(sut.current.value.isNone()).isTrue();
      });
}
