/// Rejects an int key hive can't store exactly. hive keeps ints as 64-bit floats, so past 2^53 some come
/// back as a neighbour, and 2 keys of one map would come back as a single entry.
///
/// Runs in release on purpose, like the raw-key gate: the ints that trip it are data-derived, like
/// 64-bit server ids, the kind development runs rarely see.
void ensureExactIntKey(int key) {
  if (key.toDouble().toInt() == key) return;

  throw ArgumentError.value(
    key,
    'key',
    "hive stores ints as 64-bit floats and can't hold this one exactly, so after a restart it would "
        'read back as a different key',
  );
}
