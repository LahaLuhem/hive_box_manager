import 'dart:convert';

import 'constants/hive_key_limits.dart';

/// Rejects the raw keys release-mode hive_ce would take and then corrupt on. Out-of-range ints wrap
/// round without a word, and an oversized String key leaves the box file unreadable next time you open
/// it.
///
/// Runs in release on purpose, the one carve-out from the assert-first rule, because hive's own guard
/// is assert-stripped there. Why that is worth it: APPENDIX #key-strategy.
///
/// Reads and deletes skip it. Reads cannot corrupt anything, and hive no-ops a delete of a key that
/// isn't there before it writes a frame.
void ensureStorableRawKey(Object rawKey) {
  switch (rawKey) {
    case final int key:
      if (key < 0 || key > HiveKeyLimits.maxIntKey) {
        throw ArgumentError.value(
          key,
          'key',
          'raw int keys must be within 0..0xFFFFFFFF (u32): release-mode hive_ce silently wraps '
              'out-of-range keys into that domain, corrupting the write',
        );
      }
    case final String key:
      // One UTF-16 unit encodes to at most 3 UTF-8 bytes, so short keys skip the byte count.
      if (key.length * 3 > HiveKeyLimits.maxStringKeyBytes &&
          utf8.encode(key).length > HiveKeyLimits.maxStringKeyBytes) {
        throw ArgumentError.value(
          key,
          'key',
          'raw String keys must be at most ${HiveKeyLimits.maxStringKeyBytes} UTF-8 bytes: '
              'release-mode '
              'hive_ce accepts longer keys and the box file becomes unreadable on next open',
        );
      }
    default:
      throw ArgumentError.value(
        rawKey,
        'key',
        'raw keys must be int or String (the KeyCodec contract); hive stores nothing else',
      );
  }
}
