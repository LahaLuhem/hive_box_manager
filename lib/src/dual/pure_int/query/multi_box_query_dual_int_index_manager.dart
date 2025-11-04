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
