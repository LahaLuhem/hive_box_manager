// The dual-key demo's behaviour through its view-model: grid seeding and the reverse queries by
// either part, against real hive on a temp dir. The two query axes and the no-match case are
// rows of one scenario, read back through the context.
import 'dart:io';

import 'package:bdd_framework/bdd_framework.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/dual_query/dual_query_view_model.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late DualQueryViewModel sut;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_example_dual_');
    Hive.init(tempDir.path);
    sut = DualQueryViewModel()..init();
  });

  tearDown(() async {
    sut.onUnmount();
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  final feature = BddFeature('Dual-key query demo');

  Bdd(feature)
      .scenario('Reverse queries answer by exactly the requested part.')
      .given('A seeded 3x3 (user, day) grid.')
      .when('The user queries by one axis with one part value.')
      .then('Exactly the matching entries come back, empty when nothing matches.')
      .example(
        val('axis', 'user'),
        val('part', 2),
        val('matches', ['user 2 / day 1', 'user 2 / day 2', 'user 2 / day 3']),
      )
      .example(
        val('axis', 'day'),
        val('part', 3),
        val('matches', ['user 1 / day 3', 'user 2 / day 3', 'user 3 / day 3']),
      )
      .example(val('axis', 'user'), val('part', 9), val('matches', <String>[]))
      .example(val('axis', 'day'), val('part', 9), val('matches', <String>[]))
      .run((ctx) async {
        final axis = ctx.example.val('axis') as String;
        final part = ctx.example.val('part') as int;
        final matches = ctx.example.val('matches') as List<String>;
        await sut.onSeedPressed();

        sut.partController.text = '$part';
        await (axis == 'user' ? sut.onQueryByUserPressed() : sut.onQueryByDayPressed());

        check(sut.results.value).deepEquals(matches);
      });
}
