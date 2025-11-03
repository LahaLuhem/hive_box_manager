// Matching signature
// ignore_for_file: avoid_annotating_with_dynamic, avoid-dynamic

part of 'queryable_test.dart';

final class _FakeBitShiftQueryDualIntIndexLazyBoxManager<T extends Object>
    extends BitShiftQueryDualIntIndexLazyBoxManager<T> {
  _FakeBitShiftQueryDualIntIndexLazyBoxManager({required super.defaultValue})
    : super(boxKey: 'fake');

  @override
  Future<void> init({HiveCipher? encryptionCipher}) async => lazyBox = _FakeIntLazyBox<T>();

  @visibleForTesting
  void addAllEntries(Map<int, T> entries) => (lazyBox as _FakeIntLazyBox<T>).addAllEntries(entries);
}

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
