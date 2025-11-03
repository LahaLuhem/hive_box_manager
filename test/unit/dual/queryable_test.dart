import 'package:collection/collection.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:shouldly/shouldly.dart';
import 'package:test/test.dart';

part 'fakes.dart';

void main() {
  group('Query tests', () {
    const maxIndex = 10;
    final sut = FakeBitShiftQueryDualIntIndexLazyBoxManager(defaultValue: '');
    final existingBoxEntries = Iterable.generate(
      maxIndex,
      (index) => [(index, index), (index, index + 1), (index + 1, index)],
    ).flattened.append((maxIndex, maxIndex));
    final testData = Map.fromIterables(
      existingBoxEntries,
      existingBoxEntries.map((e) => '(${e.$1},${e.$2})'),
    );
    sut._mockBox.addAll(
      Map.fromIterables(
        testData.keys.map((e) => BitShiftQueryDualIntIndexLazyBoxManager.encoder(e.$1, e.$2)),
        testData.values,
      ),
    );

    const queriedIndex = 5;
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
