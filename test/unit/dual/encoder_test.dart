import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:shouldly/shouldly_bool.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  group('Encoder Tests', () {
    const maxIndex = 10_000; // Max tested: 20_000

    test('Range uniqueness (Just a formality. Mathematically proven.)', () async {
      final result = await runParallelEncoderTest(
        encoder: DualIntIndexLazyBoxManager.bitShiftEncoder,
        maxIndex: maxIndex,
        primaryIndexGenerator: positiveIndexGenerator,
        secondaryIndexGenerator: positiveIndexGenerator,
      );
      result.should.beTrue();
    }, timeout: Timeout.none);

    test('Negative indices uniqueness (Just a formality. Mathematically proven.)', () async {
      final result = await runParallelEncoderTest(
        encoder: DualIntIndexLazyBoxManager.negativeNumbersEncoder,
        maxIndex: (maxIndex / 2).ceil(),
        primaryIndexGenerator: signedIndexGenerator,
        secondaryIndexGenerator: signedIndexGenerator,
        additionalChecks: [
          (primary, secondary, value) {
            if (value < 0) throw TestFailure('Negative value at ($primary, $secondary) = $value');
          },
        ],
      );
      result.should.beTrue();
    }, timeout: Timeout.none);
  }, timeout: Timeout.none);
}
