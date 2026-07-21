// IntKeyCodec is a pure pass-through; this pin keeps it honest (a future "helpful" transform in
// either direction would break stored-data compatibility).
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/key/int_key_codec.dart';
import 'package:hive_box_manager/src/core/constants/hive_key_limits.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

void main() {
  feature('IntKeyCodec', () {
    scenarioOutline<int>(
      'round-trips raw int keys untouched',
      examples: {'zero': 0, 'one': 1, 'mid-range': 123456, 'u32 max': HiveKeyLimits.maxIntKey},
      outline: (key) {
        const codec = IntKeyCodec();
        final rawKey = codec.encode(key);

        check(rawKey).equals(key);
        check(codec.decode(rawKey)).equals(key);
      },
    );
  });
}
