@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/exact_int_gate.dart';
import 'package:test/test.dart';

import '../../support/support.dart';

void main() {
  feature('whether hive keeps an int exactly', () {
    scenarioOutline<int>(
      'an int a double holds is kept',
      examples: {
        'zero': 0,
        'a negative': -1,
        '2^53': 1 << 53,
        '-2^53': -(1 << 53),
        '2^53 + 2, past the range every int fits': (1 << 53) + 2,
      },
      outline: (value) => check(hiveKeepsExactly(value)).isTrue(),
    );

    scenarioOutline<int>(
      "an int a double can't hold isn't",
      examples: {
        '2^53 + 1': ProbeKeyLimits.firstWebImpreciseInt,
        '-(2^53 + 1)': -ProbeKeyLimits.firstWebImpreciseInt,
      },
      outline: (value) => check(hiveKeepsExactly(value)).isFalse(),
    );
  });

  feature('the exact-int key gate', () {
    scenario('an int key hive keeps passes', () {
      check(() => ensureExactIntKey((1 << 53) + 2)).returnsNormally();
    });

    scenario('an int key hive would change fails, naming the key', () {
      const key = ProbeKeyLimits.firstWebImpreciseInt;

      check(() => ensureExactIntKey(key))
          .throws<ArgumentError>()
          .has((error) => error.invalidValue, 'invalidValue')
          .equals(key);
    });
  });
}
