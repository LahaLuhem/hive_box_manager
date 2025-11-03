import 'dart:math' as math;

import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:shouldly/shouldly.dart';
import 'package:test/test.dart';

part 'fakes.dart';

void main() {
  group('Bit-shift query tests', () {
    const maxIndex = 10;
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

    test('Primary decomposition (positive)', () async {
      final queriedValue = testData.keys.elementAt(random.nextInt(existingBoxEntries.length)).$1;
      final primaryQueryResults = await sut.queryByPrimary(queriedValue).run();
      final expectedResults = testData.keys
          .where((e) => e.$1 == queriedValue)
          .map((e) => testData[e]!)
          .toList(growable: false);
      primaryQueryResults.should.beOfType<Some<List<String>>>();
      primaryQueryResults.getOrElse(() => const []).should.be(expectedResults);
    });
    test('Secondary decomposition (positive)', () async {
      final queriedValue = testData.keys.elementAt(random.nextInt(existingBoxEntries.length)).$2;
      final secondaryQueryResults = await sut.queryBySecondary(queriedValue).run();
      final expectedResults = testData.keys
          .where((e) => e.$2 == queriedValue)
          .map((e) => testData[e]!)
          .toList(growable: false);
      secondaryQueryResults.should.beOfType<Some<List<String>>>();
      secondaryQueryResults.getOrElse(() => const []).should.be(expectedResults);
    });

    final nonExistentIndex = existingBoxEntries.length + 1;
    test('Primary decomposition (negative)', () async {
      final primaryQueryResults = await sut.queryByPrimary(nonExistentIndex).run();
      primaryQueryResults.should.beOfType<None>();
    });
    test('Secondary decomposition (negative)', () async {
      final secondaryQueryResults = await sut.queryBySecondary(nonExistentIndex).run();
      secondaryQueryResults.should.beOfType<None>();
    });
  });
}
