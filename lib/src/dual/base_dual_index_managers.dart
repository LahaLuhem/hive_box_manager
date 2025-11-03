import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '../base_box_manager.dart';
import '../const_values.dart';
import '../typedefs.dart';

part 'pure_int/dual_int_index_managers.dart';
part 'base_query_dual_index_managers.dart';
part 'pure_int/query_dual_int_index_managers.dart';

abstract class _BaseDualIndexLazyBoxManager<T, I1, I2, O extends Object>
    extends BaseBoxManager<T, O> {
  _BaseDualIndexLazyBoxManager({
    required super.boxKey,
    required super.defaultValue,
    required Encoder<I1, I2, O> encoder,
    super.logCallback,
  }) : _encoder = encoder;

  late final LazyBox<T> _lazyBox;
  final Encoder<I1, I2, O> _encoder;

  @override
  Future<void> init({HiveCipher? encryptionCipher}) async =>
      _lazyBox = await Hive.openLazyBox(boxKey, encryptionCipher: encryptionCipher);

  Task<T> get({required I1 primaryIndex, required I2 secondaryIndex}) => Task(
    () async =>
        (await _lazyBox.get(_encoder(primaryIndex, secondaryIndex), defaultValue: defaultValue))
            as T,
  );

  TaskOption<T> tryGet({required I1 primaryIndex, required I2 secondaryIndex}) => TaskOption(
    () async => Option.fromNullable(
      await _lazyBox.get(_encoder(primaryIndex, secondaryIndex), defaultValue: null),
    ),
  );

  Task<List<T>> getAll() => Task(() async {
    if (_lazyBox.isEmpty) return const [];

    // Non-empty indices should have a value => no need for [defaultValue]
    return _lazyBox.keys
        .map((index) async => (await _lazyBox.get(index)) as T)
        .toList(growable: false)
        .wait;
  });

  TaskOption<List<T>> tryGetAll() =>
      _lazyBox.isEmpty ? TaskOption.none() : TaskOption.fromTask(getAll());

  Task<Unit> put({required I1 primaryIndex, required I2 secondaryIndex, required T value}) =>
      Task(() {
        final encodedIndex = _encoder(primaryIndex, secondaryIndex);

        return _lazyBox
            .put(encodedIndex, value)
            .then((_) => logCallback?.call(_defaultLogCallback(encodedIndex, value)));
      }).map((_) => unit);

  Task<Unit> putAll({
    required Iterable<T> values,
    required (I1, I2) Function(T value) indexTransformer,
  }) => Task(
    () => _lazyBox
        .putAll(
          Map.fromIterables(
            values.map((value) {
              final primaryAndSecondaryIndices = indexTransformer(value);

              return _encoder(primaryAndSecondaryIndices.$1, primaryAndSecondaryIndices.$2);
            }),
            values,
          ),
        )
        .then(
          (_) => logCallback?.call('Wrote ${values.length} key-value pairs to LazyBox[$boxKey]'),
        ),
  ).map((_) => unit);

  Task<Unit> upsert({
    required I1 primaryIndex,
    required I2 secondaryIndex,
    required BoxUpdater<T> boxUpdater,
    LogPattern<O, T>? logPattern,
  }) => get(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex).flatMap((currentValue) {
    final updatedValue = boxUpdater.call(currentValue);

    return Task(() {
      final encodedIndex = _encoder(primaryIndex, secondaryIndex);

      return _lazyBox
          .put(encodedIndex, updatedValue)
          .then((_) => logCallback?.call(_defaultLogCallback(encodedIndex, updatedValue)));
    }).map((_) => unit);
  });

  Task<Unit> delete({required I1 primaryIndex, required I2 secondaryIndex}) => Task(() {
    final encodedIndex = _encoder(primaryIndex, secondaryIndex);

    return _lazyBox
        .delete(encodedIndex)
        .then((_) => logCallback?.call("Deleted from LazyBox[$boxKey] at '$encodedIndex'"));
  }).map((_) => unit);

  String _defaultLogCallback(O index, T value) =>
      "Wrote to LazyBox[$boxKey] at '$index' with $value";
}
