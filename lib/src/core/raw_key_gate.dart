import 'dart:convert';

import 'constants/hive_key_limits.dart';

/// The write-path corruption gate: rejects raw keys that release-mode hive_ce would accept and
/// then corrupt on (out-of-range int keys wrap silently; oversized String keys make the whole box file unreadable on the next open).
///
/// Runs in release deliberately, the one sanctioned carve-out from the assert-first rule: the engine's
/// own guard (`Frame.assertKey`) is assert-stripped in release, and the violating class of key
/// (data-derived, e.g. 64-bit server ids) is exactly the class development runs never see. Cost:
/// two comparisons, plus a UTF-8 byte count for long String keys only, against a write that costs ~10 us.
///
/// Reads and deletes never gate: reads cannot corrupt, and hive no-ops a delete of an absent key
/// before writing any frame, so a key this gate never admitted cannot reach disk that way.
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
