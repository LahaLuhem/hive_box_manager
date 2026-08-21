// The perf opt-in dual codec: 16-bit parts, u32 raw keys, byte-identical to 0.0.x bit-shift.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/dual/packed_int_dual_codec.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

/// Part values at the edges of the 16-bit domain.
const boundaryParts = [0, 1, 42, PackedIntDualCodec.maxPart - 1, PackedIntDualCodec.maxPart];

void main() {
  feature('PackedIntDualCodec', () {
    scenario('round-trips exactly and stays in u32 across the boundary matrix', () {
      const codec = PackedIntDualCodec();
      for (final primary in boundaryParts) {
        for (final secondary in boundaryParts) {
          final rawKey = codec.encode(primary, secondary) as int;

          check(rawKey).isGreaterOrEqual(0);
          check(codec.decode(rawKey)).equals((primary, secondary));
        }
      }
    });

    scenario('is byte-identical to the 0.0.x bit-shift scheme for in-range parts', () {
      const codec = PackedIntDualCodec();
      for (final primary in boundaryParts) {
        for (final secondary in boundaryParts) {
          check(codec.encode(primary, secondary))
              .equals((primary << PackedIntDualCodec.bitsPerPart) | secondary);
        }
      }
    });

    scenarioOutline<(int, int)>(
      'out-of-domain parts fail the development assert',
      examples: {
        'negative primary': (-1, 0),
        'negative secondary': (0, -1),
        'primary past the ceiling': (PackedIntDualCodec.maxPart + 1, 0),
        'secondary past the ceiling': (0, PackedIntDualCodec.maxPart + 1),
      },
      outline: (parts) {
        const codec = PackedIntDualCodec();

        check(() => codec.encode(parts.$1, parts.$2)).throws<AssertionError>();
      },
    );
  });
}
