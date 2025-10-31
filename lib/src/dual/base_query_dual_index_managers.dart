part of 'base_dual_index_managers.dart';

abstract class _BaseQueryDualIndexLazyBoxManager<T, I1, I2, O extends Object>
    extends _BaseDualIndexLazyBoxManager<T, I1, I2, O> {
  _BaseQueryDualIndexLazyBoxManager({
    required super.boxKey,
    required super.defaultValue,
    required super.encoder,
    required Decomposer<I2, I1> primariesDecomposer,
    required Decomposer<I1, I2> secondariesDecomposer,
    super.logCallback,
  }) : _primariesDecomposer = primariesDecomposer,
       _secondariesDecomposer = secondariesDecomposer;

  final Iterable<I1> Function(I2 secondaryIndex) _primariesDecomposer;
  final Iterable<I2> Function(I1 primaryIndex) _secondariesDecomposer;

  Task<List<T>> queryByPrimary(I1 primaryIndex) => _secondariesDecomposer(primaryIndex)
      .map((secondaryIndex) => get(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex))
      .sequenceTask();

  Task<List<T>> queryBySecondary(I2 secondaryIndex) => _primariesDecomposer(secondaryIndex)
      .map((primaryIndex) => get(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex))
      .sequenceTask();
}
