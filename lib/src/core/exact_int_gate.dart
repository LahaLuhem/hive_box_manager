import 'package:meta/meta.dart';

/// Whether hive gives [value] back unchanged. It keeps ints as 64-bit floats, so past 2^53 some come
/// back as a neighbour.
@internal
bool hiveKeepsExactly(int value) =>
    // Every int within ±2^53 fits a float, so only bigger ones pay for the round trip.
    (value >= -_twoTo53 && value <= _twoTo53) || value.toDouble().toInt() == value;

const _twoTo53 = 9007199254740992;

/// Rejects an int key hive would change, since 2 keys of one map could come back as one entry.
///
/// Runs in release on purpose, like the raw-key gate: the ints that trip it are data-derived, like
/// 64-bit server ids, the kind development runs rarely see.
@internal
void ensureExactIntKey(int key) {
  if (hiveKeepsExactly(key)) return;

  throw ArgumentError.value(
    key,
    'key',
    "hive stores ints as 64-bit floats and can't hold this one exactly, so after a restart it would "
        'read back as a different key',
  );
}

/// [ensureExactIntKey] for an int inside a value, release mode included. Its own gate so the advice
/// can offer a BigInt, which a map key can't be.
@internal
void ensureExactIntValue(int value) {
  if (hiveKeepsExactly(value)) return;

  throw ArgumentError.value(
    value,
    'value',
    "hive stores ints as 64-bit floats and can't hold this one exactly, so after a restart it would "
        'read back as a different number. Store it as a String or BigInt, or keep JSON as text',
  );
}
