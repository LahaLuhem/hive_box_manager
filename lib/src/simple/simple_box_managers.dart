import 'package:collection/collection.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';

import '../base_box_manager.dart';
import '../typedefs.dart';

part 'collection_box_managers.dart';

final class BoxManager<T, I extends Object> extends BaseBoxManager<T, I> {
  BoxManager({required super.boxKey, required super.defaultValue, super.logCallback});

  late final Box<T> _box;

  @override
  Future<void> init({HiveCipher? encryptionCipher}) async =>
      _box = await Hive.openBox(super.boxKey, encryptionCipher: encryptionCipher);

  T get(I index) => _box.get(index, defaultValue: defaultValue)!;

  Task<Unit> put({required I index, required T value}) => Task(
    () => _box
        .put(index, value)
        .then((_) => logCallback?.call("Wrote to Box[$boxKey] at '$index' with $value")),
  ).map((_) => unit);

  Task<Unit> upsert({required I index, required BoxUpdater<T> boxUpdater}) => Task(() {
    final updatedValue = boxUpdater.call(get(index));

    return _box
        .put(index, updatedValue)
        .then((_) => logCallback?.call("Upserted Box[$boxKey] at '$index' with $updatedValue"));
  }).map((_) => unit);
}

final class LazyBoxManager<T, I extends Object> extends BaseBoxManager<T, I> {
  LazyBoxManager({required super.boxKey, required super.defaultValue, super.logCallback});

  late final LazyBox<T> _lazyBox;

  @override
  Future<void> init({HiveCipher? encryptionCipher}) async =>
      _lazyBox = await Hive.openLazyBox(super.boxKey, encryptionCipher: encryptionCipher);

  Task<Unit> clear() => Task(() => _lazyBox.clear()).map((_) => unit);

  Task<T> get(I index) =>
      Task(() async => (await _lazyBox.get(index, defaultValue: defaultValue))!);

  TaskOption<T> tryGet(I index) =>
      TaskOption(() async => Option.fromNullable(await _lazyBox.get(index, defaultValue: null)));

  Task<List<T>> getAll() => Task(() async {
    final indices = _lazyBox.keys;
    if (indices.isEmpty) return const [];

    // Non-empty indices should have a value => no need for [defaultValue]
    return indices.map((index) async => (await _lazyBox.get(index))!).wait;
  });

  /// Returns [TaskOption.none()] if the box is empty.
  TaskOption<List<T>> tryGetAll() =>
      _lazyBox.isEmpty ? TaskOption.none() : TaskOption.fromTask(getAll());

  Task<Unit> put({required I index, required T value, LogPattern<I, T>? logPattern}) => Task(
    () => _lazyBox
        .put(index, value)
        .then(
          (_) => logCallback?.call(
            logPattern?.call(boxKey, index, value) ?? _defaultLogCallback(boxKey, index, value),
          ),
        ),
  ).map((_) => unit);

  Task<Unit> putAll({required Iterable<T> values, required I Function(T value) indexTransformer}) =>
      Task(
        () => _lazyBox
            .putAll(Map.fromIterables(values.map(indexTransformer), values))
            .then(
              (_) =>
                  logCallback?.call('Wrote ${values.length} key-value pairs to LazyBox[$boxKey]'),
            ),
      ).map((_) => unit);

  Task<Unit> upsert({
    required I index,
    required BoxUpdater<T> boxUpdater,
    LogPattern<I, T>? logPattern,
  }) => get(index).flatMap((currentValue) {
    final updatedValue = boxUpdater.call(currentValue);

    return Task(
      () => _lazyBox
          .put(index, updatedValue)
          .then(
            (_) => logCallback?.call(
              logPattern?.call(boxKey, index, updatedValue) ??
                  _defaultLogCallback(boxKey, index, updatedValue),
            ),
          ),
    ).map((_) => unit);
  });

  Task<Unit> delete(I index) => Task(
    () => _lazyBox
        .delete(index)
        .then((_) => logCallback?.call("Deleted from LazyBox[$boxKey] at '$index'")),
  ).map((_) => unit);

  String _defaultLogCallback(String key, I index, T value) =>
      "Wrote to LazyBox[$key] at '$index' with $value";
}
