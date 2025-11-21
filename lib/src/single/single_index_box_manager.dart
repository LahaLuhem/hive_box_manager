import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';

import '../base_box_manager.dart';
import '../extensions.dart';
import '../typedefs.dart';

final class SingleIndexBoxManager<T> extends BaseBoxManager<T, int> {
  late final Box<T> _box;
  static const _defaultSingleIndex = 0;

  SingleIndexBoxManager({required super.boxKey, required super.defaultValue});

  @override
  Future<void> init({HiveCipher? encryptionCipher}) async =>
      _box = await Hive.openBox(boxKey, encryptionCipher: encryptionCipher);

  @override
  Stream<BoxEvent> watchStream() => _box.watch();

  T get() => _box.get(_defaultSingleIndex, defaultValue: defaultValue)!;

  Task<Unit> put({required T value}) => Task(
    () => _box
        .put(_defaultSingleIndex, value)
        .then((_) => assignedLogCallback?.call('Wrote to SingleIndexBox[$boxKey] with $value')),
  ).mapToUnit();

  Task<Unit> upsert({required BoxUpdater<T> boxUpdater}) => Task(() {
    final updatedValue = boxUpdater.call(get());

    return _box
        .put(_defaultSingleIndex, updatedValue)
        .then(
          (_) => assignedLogCallback?.call('Upserted SingleIndexBox[$boxKey] with $updatedValue'),
        );
  }).mapToUnit();

  Task<Unit> delete() => Task(
    () => _box
        .delete(_defaultSingleIndex)
        .then((_) => assignedLogCallback?.call('Deleted from SingleIndexBox[$boxKey]')),
  ).mapToUnit();

  Task<Unit> clear() => Task(() => _box.clear()).mapToUnit();
}
