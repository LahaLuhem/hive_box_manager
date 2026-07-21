// The construction-time codec defaulting: identity codecs for int / String keys, an explicit
// codec always winning, and any other K without a codec failing the wiring assert (tier 1).
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/key/int_key_codec.dart';
import 'package:hive_box_manager/src/codec/key/key_codec_resolution.dart';
import 'package:hive_box_manager/src/codec/key/string_key_codec.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';
import '../../../support/date_key_codec.dart';

void main() {
  feature('key-codec resolution at wiring time', () {
    scenario('int keys default to the int identity codec', () {
      check(resolveKeyCodec<int>(null)).isA<IntKeyCodec>();
    });

    scenario('String keys default to the String identity codec', () {
      check(resolveKeyCodec<String>(null)).isA<StringKeyCodec>();
    });

    scenario('an explicit codec always wins, whatever K is', () {
      const dateCodec = DateKeyCodec();
      const intCodec = IntKeyCodec();

      check(identical(resolveKeyCodec<DateTime>(dateCodec), dateCodec)).isTrue();
      check(identical(resolveKeyCodec<int>(intCodec), intCodec)).isTrue();
    });

    scenario('any other K without a codec fails the wiring assert', () {
      check(() => resolveKeyCodec<DateTime>(null)).throws<AssertionError>();
    });
  });
}
