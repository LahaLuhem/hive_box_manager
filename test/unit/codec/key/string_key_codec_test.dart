// StringKeyCodec is a pure pass-through; this pin keeps it honest (a future "helpful" transform
// in either direction would break stored-data compatibility).
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/key/string_key_codec.dart';
import 'package:hive_box_manager/src/core/constants/hive_key_limits.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

void main() {
  feature('StringKeyCodec', () {
    scenarioOutline<String>(
      'round-trips raw String keys untouched',
      examples: {
        'plain': 'user-7',
        'non-ASCII': 'héllo',
        'separator-looking': '12:34',
        'at the byte limit': 'a' * HiveKeyLimits.maxStringKeyBytes,
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
