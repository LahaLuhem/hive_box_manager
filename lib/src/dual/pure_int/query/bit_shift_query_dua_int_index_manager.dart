part of '../../base_dual_index_managers.dart';

/// Uses Hive.keys for O(K) decomposition instead of O(65536)
/// Made not final just for testing.
@protected
@visibleForTesting
class BitShiftQueryDualIntIndexLazyBoxManager<T extends Object>
    extends QueryDualIntIndexLazyBoxManager<T> {
  @protected
  @override
  Iterable<int> primariesDecomposer(int secondaryIndex) sync* {
    final seen = <int>{};
    for (final key in boxKeys) {
      final (primary, secondary) = _decode(key);
      if (secondary == secondaryIndex && seen.add(primary)) {
        yield primary;
      }
    }
  }

  @protected
  @override
  Iterable<int> secondariesDecomposer(int primaryIndex) sync* {
    final seen = <int>{};
    for (final key in boxKeys) {
      final (primary, secondary) = _decode(key);
      if (primary == primaryIndex && seen.add(secondary)) {
        yield secondary;
      }
    }
  }

  @protected
  @visibleForTesting
  static int encoder(int primaryIndex, int secondaryIndex) =>
      DualIntIndexLazyBoxManager.bitShiftEncoder(primaryIndex, secondaryIndex);

  static (int, int) _decode(int encodedKey) => (
    (encodedKey >> ConstValues.bitShift) & ConstValues.bitMask,
    encodedKey & ConstValues.bitMask,
  );

  @protected
  @visibleForTesting
  BitShiftQueryDualIntIndexLazyBoxManager({required super.boxKey, required super.defaultValue})
    : super._(encoder: encoder);
}
