/// A plain copy of [entries] for hive, so it never holds a map with its own equality, and later edits
/// to [entries] can't reach its cache.
Map<MK, MV> storableCopyOf<MK extends Object, MV extends Object>(Map<MK, MV> entries) =>
    Map<MK, MV>.of(entries);
