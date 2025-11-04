import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '../base_box_manager.dart';
import '../const_values.dart';
import '../extensions.dart';
import '../typedefs.dart';

part 'pure_int/dual_int_index_managers.dart';
part 'base_query_dual_index_managers.dart';
part 'pure_int/query/query_dual_int_index_managers.dart';
part 'pure_int/query/bit_shift_query_dua_int_index_manager.dart';
part 'pure_int/query/multi_box_query_dual_int_index_manager.dart';

abstract class _BaseDualIndexLazyBoxManager<T, I1, I2, O extends Object>
    extends BaseBoxManager<T, O> {
  _BaseDualIndexLazyBoxManager({
    required super.boxKey,
    required super.defaultValue,
    required Encoder<I1, I2, O> encoder,
  }) : _encoder = encoder;

  @protected
  @visibleForTesting
  late final LazyBox<T> lazyBox;
  final Encoder<I1, I2, O> _encoder;

  @override
  Future<void> init({HiveCipher? encryptionCipher}) async =>
      lazyBox = await Hive.openLazyBox(boxKey, encryptionCipher: encryptionCipher);

  Task<T> get({required I1 primaryIndex, required I2 secondaryIndex}) => Task(
    () async =>
        (await lazyBox.get(_encoder(primaryIndex, secondaryIndex), defaultValue: defaultValue))
            as T,
  );

  TaskOption<T> tryGet({required I1 primaryIndex, required I2 secondaryIndex}) => TaskOption(
    () async => Option.fromNullable(
      await lazyBox.get(_encoder(primaryIndex, secondaryIndex), defaultValue: null),
    ),
  );

  Task<List<T>> getAll() => Task(() async {
    if (lazyBox.isEmpty) return const [];

    // Non-empty indices should have a value => no need for [defaultValue]
    return lazyBox.keys
        .map((index) async => (await lazyBox.get(index)) as T)
        .toList(growable: false)
        .wait;
  });

  TaskOption<List<T>> tryGetAll() =>
      lazyBox.isEmpty ? TaskOption.none() : TaskOption.fromTask(getAll());

  Task<Unit> put({required I1 primaryIndex, required I2 secondaryIndex, required T value}) =>
      Task(() {
        final encodedIndex = _encoder(primaryIndex, secondaryIndex);

        return lazyBox
            .put(encodedIndex, value)
            .then((_) => assignedLogCallback?.call(_defaultLogCallback(encodedIndex, value)));
      }).mapToUnit();

  Task<Unit> putAll({
    required Iterable<T> values,
    required (I1, I2) Function(T value) indexTransformer,
  }) => Task(
    () => lazyBox
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
          (_) => assignedLogCallback?.call(
            'Wrote ${values.length} key-value pairs to LazyBox[$boxKey]',
          ),
        ),
  ).mapToUnit();

  Task<Unit> upsert({
    required I1 primaryIndex,
    required I2 secondaryIndex,
    required BoxUpdater<T> boxUpdater,
    LogPattern<O, T>? logPattern,
  }) => get(primaryIndex: primaryIndex, secondaryIndex: secondaryIndex).flatMap((currentValue) {
    final updatedValue = boxUpdater.call(currentValue);

    return Task(() {
      final encodedIndex = _encoder(primaryIndex, secondaryIndex);

      return lazyBox
          .put(encodedIndex, updatedValue)
          .then((_) => assignedLogCallback?.call(_defaultLogCallback(encodedIndex, updatedValue)));
    }).mapToUnit();
  });

  Task<Unit> delete({required I1 primaryIndex, required I2 secondaryIndex}) => Task(() {
    final encodedIndex = _encoder(primaryIndex, secondaryIndex);

    return lazyBox
        .delete(encodedIndex)
        .then((_) => assignedLogCallback?.call("Deleted from LazyBox[$boxKey] at '$encodedIndex'"));
  }).mapToUnit();

  Task<Unit> clear() => Task(
    () => lazyBox.clear().then((_) => assignedLogCallback?.call('Cleared LazyBox[$boxKey]')),
  ).mapToUnit();

  String _defaultLogCallback(O index, T value) =>
      "Wrote to LazyBox[$boxKey] at '$index' with $value";
}
