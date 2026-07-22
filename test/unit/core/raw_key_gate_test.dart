// The write-path corruption gate: the one release-mode check in the package, guarding exactly
// what release-mode hive_ce silently corrupts on (pinned in the integration suite).
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/raw_key_gate.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/pins/probe_key_limits.dart';

/// A 3-UTF-8-byte character (hiragana "a"): stresses the byte-vs-character distinction.
const threeByteChar = 'あ';

/// A 2-UTF-8-byte character: builds keys whose *length* passes the cheap bound but whose
/// *bytes* exceed the limit.
const twoByteChar = 'é';

void main() {
  feature('the raw-key corruption gate', () {
    scenarioOutline<Object>(
      'admits every storable raw key',
      examples: {
        'int zero': 0,
        'u32 max': HiveKeyLimits.maxIntKey,
        'short ASCII (fast path)': 'user-7',
        'exactly the byte limit, ASCII': 'a' * HiveKeyLimits.maxStringKeyBytes,
        'exactly the byte limit, multibyte': threeByteChar * (HiveKeyLimits.maxStringKeyBytes ~/ 3),
      },
      outline: (rawKey) {
        check(() => ensureStorableRawKey(rawKey)).returnsNormally();
      },
    );

    scenarioOutline<Object>(
      'rejects every corrupting raw key with an ArgumentError at the call site',
      examples: {
        'int -1': -1,
        'int one past u32': HiveKeyLimits.maxIntKey + 1,
        'one byte over, ASCII': 'b' * (HiveKeyLimits.maxStringKeyBytes + 1),
        // 128 chars pass a naive length check but encode to 256 bytes: the byte-count path
        // must engage even though the string is "short".
        'one byte over, multibyte': twoByteChar * 128,
        'far over': 'c' * ProbeKeyLimits.farOversizedKeyLength,
      },
      outline: (rawKey) {
        check(() => ensureStorableRawKey(rawKey)).throws<ArgumentError>();
      },
    );

    scenarioOutline<Object>(
      'rejects raw keys outside the int-or-String contract',
      examples: {'double': 1.5, 'bool': true, 'record': (1, 2)},
      outline: (rawKey) {
        check(() => ensureStorableRawKey(rawKey)).throws<ArgumentError>();
      },
    );
  });
}
