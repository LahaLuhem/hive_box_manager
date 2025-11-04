// Needed for the being able to store an Iterable of in one entry
// ignore_for_file: avoid-dynamic

part of 'simple_box_managers.dart';

/// Exists because Hive does not support reading Iterables of custom types.<br>
/// See (issue)[https://github.com/IO-Design-Team/hive_ce/issues/150]<br>
/// Solved by keeping the [_lazyBox] as `dynamic` and safe-casting the values around its CRUD. (Covariance)
final class CollectionLazyBoxManager<T, I extends Object> extends LazyBoxManager<dynamic, I> {
  /// When adding type-info, make sure that [T] itself is not an Iterable but the actual base type.
  CollectionLazyBoxManager({required super.boxKey, required super.defaultValue});

  @override
  Task<Iterable<T>> get(I index) =>
      super.get(index).map((value) => (value as Iterable<dynamic>).cast<T>());

  @override
  TaskOption<Iterable<T>> tryGet(I index) =>
      super.tryGet(index).map((value) => (value as Iterable<dynamic>).cast<T>());

  @override
  Task<Unit> put({
    required I index,
    required covariant Iterable<T> value,
    LogPattern<I, dynamic>? logPattern,
  }) => super.put(index: index, value: value, logPattern: _collectionLogCallback.call);

  @override
  Task<Unit> putAll({
    required covariant Iterable<T> values,
    required I Function(T value) indexTransformer,
  }) => values
      .groupListsBy(indexTransformer)
      .entries
      .map((groupedEntries) => put(index: groupedEntries.key, value: groupedEntries.value))
      .sequenceTask()
      .mapToUnit();

  @override
  Task<Unit> upsert({
    required I index,
    required BoxUpdater<dynamic> boxUpdater,
    LogPattern<I, dynamic>? logPattern,
  }) => super.upsert(index: index, boxUpdater: boxUpdater, logPattern: _collectionLogCallback.call);

  // Nature of this implementation
  //ignore: avoid_annotating_with_dynamic,
  String _collectionLogCallback(String key, I index, dynamic value) =>
      "Wrote to CollectionLazyBox[$key] at '$index' with ${(value as Iterable<dynamic>).cast<T>().length} entries";
}
