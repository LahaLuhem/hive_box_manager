// The identity codecs are pure pass-throughs; these pins keep them honest (a future "helpful"
// transformation in either direction would break stored-data compatibility).
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/int_key_codec.dart';
import 'package:hive_box_manager/src/codec/string_key_codec.dart';
import 'package:hive_box_manager/src/core/hive_key_limits.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

void main() {
  feature('identity key codecs', () {
    scenarioOutline<int>(
      'IntKeyCodec round-trips raw int keys untouched',
      examples: {'zero': 0, 'one': 1, 'mid-range': 123456, 'u32 max': hiveMaxIntKey},
      outline: (key) {
        const codec = IntKeyCodec();
        final rawKey = codec.encode(key);

        check(rawKey).equals(key);
        check(codec.decode(rawKey)).equals(key);
      },
    );

    scenarioOutline<String>(
      'StringKeyCodec round-trips raw String keys untouched',
      examples: {
        'plain': 'user-7',
        'non-ASCII': 'héllo',
        'separator-looking': '12:34',
        'at the byte limit': 'a' * hiveMaxStringKeyBytes,
      },
      outline: (key) {
        const codec = StringKeyCodec();
        final rawKey = codec.encode(key);

        check(rawKey).equals(key);
        check(codec.decode(rawKey)).equals(key);
      },
    );
  });
}
