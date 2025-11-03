import 'dart:math' as math;

import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:shouldly/shouldly.dart';
import 'package:test/test.dart';

part 'fakes.dart';

void main() {
  group('Query tests', () {
    const maxIndex = 100;
    final sut = _FakeBitShiftQueryDualIntIndexLazyBoxManager(defaultValue: '');

    final random = math.Random(42);
    final existingBoxEntries = Iterable.generate(
      maxIndex,
      (_) => (random.nextInt(maxIndex), random.nextInt(maxIndex)),
    );
    final testData = Map.fromIterables(
      existingBoxEntries,
      existingBoxEntries.map((e) => '(${e.$1},${e.$2})'),
    );

    setUpAll(() async {
      await sut.init();
      sut.addAllEntries(
        Map.fromIterables(
          testData.keys.map((e) => BitShiftQueryDualIntIndexLazyBoxManager.encoder(e.$1, e.$2)),
          testData.values,
        ),
      );
    });

    final queriedIndex = random.nextInt(existingBoxEntries.length);
    test('Primary decomposition', () async {
      final primaryQueryResults = await sut.queryByPrimary(queriedIndex).run();
      final expectedResults = testData.keys
          .where((e) => e.$1 == queriedIndex)
          .map((e) => testData[e]!)
          .toList(growable: false);
      primaryQueryResults.should.be(expectedResults);
    });
    test('Secondary decomposition', () async {
      final secondaryQueryResults = await sut.queryBySecondary(queriedIndex).run();
      final expectedResults = testData.keys
          .where((e) => e.$2 == queriedIndex)
          .map((e) => testData[e]!)
          .toList(growable: false);
      secondaryQueryResults.should.be(expectedResults);
    });
  });
}
