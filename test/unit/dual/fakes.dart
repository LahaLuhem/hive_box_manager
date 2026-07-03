// Matching signature
// ignore_for_file: avoid_annotating_with_dynamic, avoid-dynamic

part of 'queryable_test.dart';

/// In-memory stand-in for a [LazyBox], keyed by the encoded int index. Lets the
/// bit-shift query logic run against known data without opening a real Hive box.
class _FakeIntLazyBox<E> extends Fake implements LazyBox<E> {
  final Map<int, E> _mockBox = {};

  @override
  Iterable<int> get keys => _mockBox.keys;

  @override
  Future<E?> get(dynamic key, {E? defaultValue}) async => _mockBox[key] ?? defaultValue;

  @override
  Future<void> putAll(Map<dynamic, E> entries) async => _mockBox.addAll(entries.cast<int, E>());

  @visibleForTesting
  void addAllEntries(Map<int, E> entries) => _mockBox.addAll(entries);
}
