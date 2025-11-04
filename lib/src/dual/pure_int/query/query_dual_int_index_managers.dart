part of '../../base_dual_index_managers.dart';

abstract class QueryDualIntIndexLazyBoxManager<T extends Object>
    extends _BaseQueryDualIndexLazyBoxManager<T, int, int, int> {
  QueryDualIntIndexLazyBoxManager._({
    required super.boxKey,
    required super.defaultValue,
    required super.encoder,
  });

  /// ### ✅ Pros
  /// + Perfect accuracy: Always reflects current box state
  /// + Zero storage overhead: No additional boxes or memory structures
  /// + Memory efficient: Only stores seen indices during iteration
  /// + Simple & robust: Less code, fewer failure points
  /// + Leverages Hive optimizations: Uses Hive's built-in key indexing
  /// ### ❌ Cons
  /// + Still O(K) per query: Performance degrades with total records
  /// + No pre-computation: Each query scans all keys
  /// + Not optimal for very large datasets: >100K records may cause UI jank
  /// + No indexing benefits: Each decomposition is a full scan
  factory QueryDualIntIndexLazyBoxManager.bitShift({
    required String boxKey,
    required T defaultValue,
  }) = BitShiftQueryDualIntIndexLazyBoxManager;
}
