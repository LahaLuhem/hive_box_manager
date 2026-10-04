@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/exact_int_gate.dart';
import 'package:test/test.dart';

import '../../support/support.dart';

void main() {
  feature('the exact-int key gate', () {
    scenarioOutline<int>(
      'an int hive stores exactly passes',
      examples: {
        'zero': 0,
        'a negative': -1,
        '2^53': 1 << 53,
        '-2^53': -(1 << 53),
        '2^53 + 2, which a float holds exactly': (1 << 53) + 2,
      },
      outline: (key) => check(() => ensureExactIntKey(key)).returnsNormally(),
    );

    scenarioOutline<int>(
      'an int hive would read back as a neighbour fails, naming the key',
      examples: {
        '2^53 + 1': ProbeKeyLimits.firstWebImpreciseInt,
        '-(2^53 + 1)': -ProbeKeyLimits.firstWebImpreciseInt,
      },
      outline: (key) =>
          check(() => ensureExactIntKey(key))
              .throws<ArgumentError>()
              .has((error) => error.invalidValue, 'invalidValue')
              .equals(key),
    );
  });
}
