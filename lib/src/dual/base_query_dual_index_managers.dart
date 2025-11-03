part of 'base_dual_index_managers.dart';

abstract class _BaseQueryDualIndexLazyBoxManager<T, I1, I2, O extends Object>
    extends _BaseDualIndexLazyBoxManager<T, I1, I2, O> {
  _BaseQueryDualIndexLazyBoxManager({
    required super.boxKey,
    required super.defaultValue,
    required super.encoder,
    super.logCallback,
  });

  @protected
  @visibleForOverriding
  Iterable<I1> primariesDecomposer(I2 secondaryIndex);

  @protected
  @visibleForOverriding
  Iterable<I2> secondariesDecomposer(I1 primaryIndex);

  @protected
  @nonVirtual
  Task<List<T>> queryByPrimary(I1 primaryIndex) => secondariesDecomposer(primaryIndex)
      .map((secondaryIndex) => get(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex))
      .sequenceTask();

  @protected
  @nonVirtual
  Task<List<T>> queryBySecondary(I2 secondaryIndex) => primariesDecomposer(secondaryIndex)
      .map((primaryIndex) => get(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex))
      .sequenceTask();
}
