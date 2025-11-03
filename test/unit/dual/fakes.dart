part of 'queryable_test.dart';
final class FakeBitShiftQueryDualIntIndexLazyBoxManager<T extends Object> extends
    BitShiftQueryDualIntIndexLazyBoxManager<T> {
  final Map<int, T> _mockBox = {};

  FakeBitShiftQueryDualIntIndexLazyBoxManager({required super.defaultValue}): super(boxKey: 'fake');

  @override
  Iterable<int> get boxKeys => _mockBox.keys;

  @override
  Task<T> get({required int primaryIndex, required int secondaryIndex}) => Task.of(_mockBox.lookup(BitShiftQueryDualIntIndexLazyBoxManager.encoder(primaryIndex, secondaryIndex)).getOrElse(() => defaultValue));

  @override
  Task<Unit> putAll({required Iterable<T> values, required (int, int) Function(T value) indexTransformer}) {
    _mockBox.addAll(Map.fromIterables(
      values.map((value) {
        final primaryAndSecondaryIndices = indexTransformer(value);

        return BitShiftQueryDualIntIndexLazyBoxManager.encoder(primaryAndSecondaryIndices.$1, primaryAndSecondaryIndices.$2);
      }),
      values,
    ));

    return Task.of(unit);
  }
}
