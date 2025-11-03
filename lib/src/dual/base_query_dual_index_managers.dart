part of 'base_dual_index_managers.dart';

abstract class _BaseQueryDualIndexLazyBoxManager<T, I1, I2, O extends Object>
    extends _BaseDualIndexLazyBoxManager<T, I1, I2, O> {
  _BaseQueryDualIndexLazyBoxManager({
    required super.boxKey,
    required super.defaultValue,
    required super.encoder,
  });

  @protected
  @visibleForOverriding
  Iterable<I1> primariesDecomposer(I2 secondaryIndex);

  @protected
  @visibleForOverriding
  Iterable<I2> secondariesDecomposer(I1 primaryIndex);

  @protected
  @visibleForTesting
  Iterable<O> get boxKeys => lazyBox.keys.cast<O>();

  @nonVirtual
  TaskOption<List<T>> queryByPrimary(I1 primaryIndex) => secondariesDecomposer(primaryIndex)
      .map((secondaryIndex) => tryGet(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex))
      .sequenceTaskOption()
      .flatMap(
        (searchResults) => TaskOption.fromPredicate(searchResults, (_) => searchResults.isNotEmpty),
      );

  @nonVirtual
  TaskOption<List<T>> queryBySecondary(I2 secondaryIndex) => primariesDecomposer(secondaryIndex)
      .map((primaryIndex) => tryGet(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex))
      .sequenceTaskOption()
      .flatMap(
        (searchResults) => TaskOption.fromPredicate(searchResults, (_) => searchResults.isNotEmpty),
      );
}
