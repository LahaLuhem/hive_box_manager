// The construction-time dual-codec defaulting: (int, int) parts default to the String
// composite, an explicit codec always wins, and any other part pair (including covariant
// supertype pairs) fails the wiring assert (tier 1).
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/dual/dual_key_codec_resolution.dart';
import 'package:hive_box_manager/src/codec/dual/packed_int_dual_codec.dart';
import 'package:hive_box_manager/src/codec/dual/string_composite_dual_codec.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/date_int_dual_codec.dart';

void main() {
  feature('dual-key-codec resolution at wiring time', () {
    scenario('(int, int) parts default to the String-composite codec', () {
      check(resolveDualKeyCodec<int, int>(null)).isA<StringCompositeDualCodec>();
    });

    scenario('an explicit codec always wins, whatever the parts are', () {
      const packed = PackedIntDualCodec();
      const dated = DateIntDualCodec();

      check(identical(resolveDualKeyCodec<int, int>(packed), packed)).isTrue();
      check(identical(resolveDualKeyCodec<DateTime, int>(dated), dated)).isTrue();
    });

    scenario('any other part pair without a codec fails the wiring assert', () {
      check(() => resolveDualKeyCodec<DateTime, int>(null)).throws<AssertionError>();
      check(() => resolveDualKeyCodec<String, String>(null)).throws<AssertionError>();
    });

    scenario('covariant supertype parts cannot silently fit the default', () {
      check(() => resolveDualKeyCodec<Object, Object>(null)).throws<AssertionError>();
      check(() => resolveDualKeyCodec<int, Object>(null)).throws<AssertionError>();
    });
  });
}
