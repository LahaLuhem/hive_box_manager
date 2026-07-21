// The safe-default dual codec: full-range parts, negatives included, bijective round-trip.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/dual/string_composite_dual_codec.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

// The i64 extremes, as expressions: literals this large would trip avoid_js_rounded_ints. These
// rows only ever run on the VM (the unit suite's browser lane selects browser-tagged files).
const i64Min = 1 << 63;
const i64Max = -(i64Min + 1);

void main() {
  feature('StringCompositeDualCodec', () {
    scenarioOutline<(int, int)>(
      'round-trips exactly, negatives and i64 extremes included',
      examples: {
        'zeroes': (0, 0),
        'small positives': (1, 2),
        'negatives': (-3, -7),
        'mixed signs': (-42, 42),
        'i64 extremes': (i64Min, i64Max),
      },
      outline: (parts) {
        const codec = StringCompositeDualCodec();

        check(codec.decode(codec.encode(parts.$1, parts.$2))).equals(parts);
      },
    );

    scenario('encodes as compact decimal with the documented separator', () {
      const codec = StringCompositeDualCodec();

      check(codec.encode(12, 34)).equals('12:34');
      check(codec.encode(-5, 6)).equals('-5:6');
    });

    scenario("worst case stays well inside hive's 255-byte key limit", () {
      const codec = StringCompositeDualCodec();
      final rawKey = codec.encode(i64Min, i64Min) as String;

      // Two 20-char parts (sign included) + 1 separator = 41 ASCII bytes.
      check(rawKey.length).equals(41);
    });
  });
}
