import '/src/core/exact_int_gate.dart';

/// A plain copy of [entries] for hive, so it never holds a map with its own equality, and later edits
/// to [entries] can't reach its cache. An int key hive can't store exactly fails here, at the call.
Map<MK, MV> storableCopyOf<MK extends Object, MV extends Object>(Map<MK, MV> entries) {
  // A walk of its own, since Map.of copies far faster than a loop that also checks could.
  if (_canHoldInts<MK>()) entries.keys.whereType<int>().forEach(ensureExactIntKey);

  return Map<MK, MV>.of(entries);
}

// A type can't be tested directly, but an empty list of it can.
bool _canHoldInts<T>() => <int>[] is List<T>;
