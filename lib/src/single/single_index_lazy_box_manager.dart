import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';

import '../base_box_manager.dart';
import '../typedefs.dart';

final class SingleIndexLazyBoxManager<T> extends BaseBoxManager<T, int> {
  late final LazyBox<T> _lazyBox;
  static const _defaultSingleIndex = 0;

  SingleIndexLazyBoxManager({
    required super.boxKey,
    required super.defaultValue,
    super.logCallback,
  });

  @override
  Future<void> init({HiveCipher? encryptionCipher}) async =>
      _lazyBox = await Hive.openLazyBox(boxKey, encryptionCipher: encryptionCipher);

  Task<Unit> clear() => Task(() => _lazyBox.clear()).map((_) => unit);

  Task<T> get() =>
      Task(() async => (await _lazyBox.get(_defaultSingleIndex, defaultValue: defaultValue)) as T);

  TaskOption<T> tryGet() => TaskOption(
    () async => Option.fromNullable(await _lazyBox.get(_defaultSingleIndex, defaultValue: null)),
  );

  Task<List<T>> getAll() => Task(() async {
    final indices = _lazyBox.keys;
    if (indices.isEmpty) return const [];

    // Non-empty indices should have a value => no need for [defaultValue]
    return indices.map((index) async => (await _lazyBox.get(index)) as T).wait;
  });

  /// Returns [TaskOption.none()] if the box is empty.
  TaskOption<List<T>> tryGetAll() =>
      _lazyBox.isEmpty ? TaskOption.none() : TaskOption.fromTask(getAll());

  Task<Unit> put({required T value}) => Task(
    () => _lazyBox
        .put(_defaultSingleIndex, value)
        .then((_) => logCallback?.call('Wrote to SingleIndexLazyBox[$boxKey] with $value')),
  ).map((_) => unit);

  Task<Unit> upsert({required BoxUpdater<T> boxUpdater}) => get().flatMap((currentValue) {
    final updatedValue = boxUpdater.call(currentValue);

    return Task(
      () => _lazyBox
          .put(_defaultSingleIndex, updatedValue)
          .then(
            (_) => logCallback?.call('Wrote to SingleIndexLazyBox[$boxKey] with $updatedValue'),
          ),
    ).map((_) => unit);
  });

  Task<Unit> delete() => Task(
    () => _lazyBox
        .delete(_defaultSingleIndex)
        .then((_) => logCallback?.call('Deleted from SingleIndexLazyBox[$boxKey]')),
  ).map((_) => unit);
}
