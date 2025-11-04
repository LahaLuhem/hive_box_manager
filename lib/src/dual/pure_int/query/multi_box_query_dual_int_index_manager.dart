part of '../../base_dual_index_managers.dart';

class MultiBoxQueryDualIntIndexLazyBoxManager<T extends Object>
    extends QueryDualIntIndexLazyBoxManager<T> {
  late final _primaryIndexBox = CollectionLazyBoxManager<int, int>(
    boxKey: '${boxKey}_primary_index_box',
    defaultValue: const <int>[],
  );
  late final _secondaryIndexBox = CollectionLazyBoxManager<int, int>(
    boxKey: '${boxKey}_secondary_index_box',
    defaultValue: const <int>[],
  );

  @override
  Future<void> init({HiveCipher? encryptionCipher}) => [
    _primaryIndexBox.init(encryptionCipher: encryptionCipher),
    _secondaryIndexBox.init(encryptionCipher: encryptionCipher),
    super.init(encryptionCipher: encryptionCipher),
  ].wait;

  @override
  Task<Unit> put({required int primaryIndex, required int secondaryIndex, required T value}) {
    final encodedKey = encoder(primaryIndex, secondaryIndex);
    if (lazyBox.containsKey(encodedKey)) return Task.of(unit);

    // Nature of this box
    // ignore: avoid_annotating_with_dynamic, avoid-dynamic
    List<int> boxUpdater(dynamic currentValue) =>
        // Nature of this box
        // ignore: avoid-dynamic
        (currentValue as List<dynamic>).cast<int>()..add(encodedKey);

    return [
      Task(() => lazyBox.put(encodedKey, value)),
      _primaryIndexBox.upsert(index: primaryIndex, boxUpdater: boxUpdater),
      _secondaryIndexBox.upsert(index: secondaryIndex, boxUpdater: boxUpdater),
    ].sequenceTask().mapToUnit().attachAction(
      () => assignedLogCallback?.call('Wrote to LazyBox[$boxKey] at $encodedKey with $value'),
    );
  }

  @override
  Task<Unit> putAll({required Iterable<T> values, required (int, int) Function(T value) indexTransformer}) => throw UnimplementedError();
  @override
  Task<Unit> upsert({required int primaryIndex, required int secondaryIndex, required BoxUpdater<T> boxUpdater, LogPattern<int, T>? logPattern}) => throw UnimplementedError();
  @override
  Task<Unit> delete({required int primaryIndex, required int secondaryIndex}) => throw UnimplementedError();

  @override
  Task<Iterable<int>> primariesDecomposer(int secondaryIndex) => _secondaryIndexBox
      .get(secondaryIndex)
      .map(
        (encodedKeys) => encodedKeys
            .filter((key) => lazyBox.containsKey(key))
            .map((key) => (key >> ConstValues.bitShift) & ConstValues.bitMask),
      );

  @override
  Task<Iterable<int>> secondariesDecomposer(int primaryIndex) => _primaryIndexBox
      .get(primaryIndex)
      .map(
        (encodedKeys) => encodedKeys
            .filter((key) => lazyBox.containsKey(key))
            .map((key) => (key >> ConstValues.bitShift) & ConstValues.bitMask),
      );

  @protected
  @visibleForTesting
  static int encoder(int primaryIndex, int secondaryIndex) =>
      DualIntIndexLazyBoxManager.bitShiftEncoder(primaryIndex, secondaryIndex);

  @protected
  @visibleForTesting
  MultiBoxQueryDualIntIndexLazyBoxManager({required super.boxKey, required super.defaultValue})
    : super._(encoder: encoder);
}
