part of '../base_dual_index_managers.dart';

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

/// Uses Hive.keys for O(K) decomposition instead of O(65536)
/// Made not final just for testing.
@protected
@visibleForTesting
class BitShiftQueryDualIntIndexLazyBoxManager<T extends Object>
    extends QueryDualIntIndexLazyBoxManager<T> {
  @protected
  @override
  Iterable<int> primariesDecomposer(int secondaryIndex) =>
      _primariesBitShiftDecomposer(secondaryIndex: secondaryIndex, boxKeys: boxKeys);

  @protected
  @override
  Iterable<int> secondariesDecomposer(int primaryIndex) =>
      _secondariesBitShiftDecomposer(primaryIndex: primaryIndex, boxKeys: boxKeys);

  @protected
  @visibleForTesting
  static int encoder(int primaryIndex, int secondaryIndex) =>
      bitShiftEncoder(primaryIndex, secondaryIndex);

  @protected
  @visibleForTesting
  BitShiftQueryDualIntIndexLazyBoxManager({required super.boxKey, required super.defaultValue})
    : super._(encoder: encoder);
}

abstract class QueryDualIntIndexBoxManager<T extends Object>
    extends _BaseQueryDualIndexBoxManager<T, int, int, int> {
  QueryDualIntIndexBoxManager._({
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
  factory QueryDualIntIndexBoxManager.bitShift({required String boxKey, required T defaultValue}) =
      BitShiftQueryDualIntIndexBoxManager;
}

/// Uses Hive.keys for O(K) decomposition instead of O(65536)
/// Made not final just for testing.
@protected
@visibleForTesting
class BitShiftQueryDualIntIndexBoxManager<T extends Object> extends QueryDualIntIndexBoxManager<T> {
  @protected
  @override
  Iterable<int> primariesDecomposer(int secondaryIndex) =>
      _primariesBitShiftDecomposer(secondaryIndex: secondaryIndex, boxKeys: boxKeys);

  @protected
  @override
  Iterable<int> secondariesDecomposer(int primaryIndex) =>
      _secondariesBitShiftDecomposer(primaryIndex: primaryIndex, boxKeys: boxKeys);

  @protected
  @visibleForTesting
  static int encoder(int primaryIndex, int secondaryIndex) =>
      bitShiftEncoder(primaryIndex, secondaryIndex);

  @protected
  @visibleForTesting
  BitShiftQueryDualIntIndexBoxManager({required super.boxKey, required super.defaultValue})
    : super._(encoder: encoder);
}

Iterable<int> _primariesBitShiftDecomposer({
  required int secondaryIndex,
  required Iterable<int> boxKeys,
}) sync* {
  final seen = <int>{};
  for (final key in boxKeys) {
    final (primary, secondary) = _decode(key);
    if (secondary == secondaryIndex && seen.add(primary)) yield primary;
  }
}

Iterable<int> _secondariesBitShiftDecomposer({
  required int primaryIndex,
  required Iterable<int> boxKeys,
}) sync* {
  final seen = <int>{};
  for (final key in boxKeys) {
    final (primary, secondary) = _decode(key);
    if (primary == primaryIndex && seen.add(secondary)) yield secondary;
  }
}

(int, int) _decode(int encodedKey) =>
    ((encodedKey >> ConstValues.bitShift) & ConstValues.bitMask, encodedKey & ConstValues.bitMask);
