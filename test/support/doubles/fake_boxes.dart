// Collections file
// ignore_for_file: avoid-dynamic, prefer-match-file-name

// Stateful in-memory doubles for hive's Box / LazyBox: the sanctioned hand-written fakes
// (engine CRUD is stateful, which mocks cannot express; house rule). They mimic the PINNED
// watch payloads: eager delete/clear events carry the old value, lazy ones carry null; and the
// pinned lifecycle: operations on a closed box throw HiveError, absent-key deletes are no-ops.
//
// Signatures mirror hive's own dynamic-typed interface, so the DCM ban is lifted here.
import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:mockito/mockito.dart';

/// Shared backing state + behaviour for both fakes.
mixin _FakeBoxCore on Fake {
  // Object?-keyed to match hive's dynamic-typed member signatures without per-call casts.
  final store = <Object?, Object?>{};
  final eventsController = StreamController<BoxEvent>.broadcast();

  var isClosed = false;
  var flushCount = 0;
  var compactCount = 0;
  var wasDeletedFromDisk = false;

  /// Whether delete-shaped events carry the old value (eager truth) or null (lazy truth).
  bool get emitsValueOnDelete;

  void ensureOpen() {
    if (isClosed) throw HiveError('Box has already been closed.');
  }

  Future<void> fakePut(Object? key, Object? value) {
    ensureOpen();
    store[key] = value;
    eventsController.add(BoxEvent(key, value, false));

    return Future.value();
  }

  Future<void> fakePutAll(Map<dynamic, Object?> entries) async {
    for (final entry in entries.entries) {
      await fakePut(entry.key, entry.value);
    }
  }

  Future<void> fakeDelete(Object? key) async {
    ensureOpen();
    if (!store.containsKey(key)) return;

    final oldValue = store.remove(key);
    eventsController.add(BoxEvent(key, emitsValueOnDelete ? oldValue : null, true));
  }

  Future<void> fakeDeleteAll(Iterable<dynamic> keys) async {
    // Materialised: deleting while iterating the live key view would mutate under the loop.
    for (final key in keys.toList(growable: false)) {
      await fakeDelete(key);
    }
  }

  Future<int> fakeClear() async {
    ensureOpen();
    final count = store.length;
    await fakeDeleteAll(store.keys);

    return count;
  }

  Stream<BoxEvent> fakeWatch({Object? key}) => key == null
      ? eventsController.stream
      : eventsController.stream.where((event) => event.key == key);
}

/// In-memory stand-in for an open eager [Box].
final class FakeEagerBox extends Fake with _FakeBoxCore implements Box<Object?> {
  FakeEagerBox({this.name = 'fake_eager'});

  @override
  final String name;

  @override
  bool get emitsValueOnDelete => true;

  @override
  bool get isOpen => !isClosed;

  @override
  int get length => store.length;

  @override
  bool get isEmpty => store.isEmpty;

  @override
  bool get isNotEmpty => store.isNotEmpty;

  @override
  Iterable<dynamic> get keys => store.keys;

  @override
  Iterable<Object?> get values => store.values;

  @override
  bool containsKey(key) => store.containsKey(key);

  @override
  Object? get(key, {Object? defaultValue}) {
    ensureOpen();

    return store[key as Object?] ?? defaultValue;
  }

  @override
  Future<void> put(key, Object? value) => fakePut(key, value);

  @override
  Future<void> putAll(Map<dynamic, Object?> entries) => fakePutAll(entries);

  @override
  Future<void> delete(key) => fakeDelete(key);

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) => fakeDeleteAll(keys);

  @override
  Future<int> clear() => fakeClear();

  @override
  Stream<BoxEvent> watch({key}) => fakeWatch(key: key);

  @override
  Future<void> flush() async {
    ensureOpen();
    flushCount++;
  }

  @override
  Future<void> compact() async {
    ensureOpen();
    compactCount++;
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> deleteFromDisk() async {
    wasDeletedFromDisk = true;
    isClosed = true;
    store.clear();
  }
}

/// In-memory stand-in for an open [LazyBox].
final class FakeLazyBox extends Fake with _FakeBoxCore implements LazyBox<Object?> {
  FakeLazyBox({this.name = 'fake_lazy'});

  @override
  final String name;

  @override
  bool get emitsValueOnDelete => false;

  @override
  bool get isOpen => !isClosed;

  @override
  int get length => store.length;

  @override
  bool get isEmpty => store.isEmpty;

  @override
  bool get isNotEmpty => store.isNotEmpty;

  @override
  Iterable<dynamic> get keys => store.keys;

  @override
  bool containsKey(key) => store.containsKey(key);

  @override
  Future<Object?> get(key, {Object? defaultValue}) async {
    ensureOpen();

    return store[key as Object?] ?? defaultValue;
  }

  @override
  Future<void> put(key, Object? value) => fakePut(key, value);

  @override
  Future<void> putAll(Map<dynamic, Object?> entries) => fakePutAll(entries);

  @override
  Future<void> delete(key) => fakeDelete(key);

  @override
  Future<void> deleteAll(Iterable<dynamic> keys) => fakeDeleteAll(keys);

  @override
  Future<int> clear() => fakeClear();

  @override
  Stream<BoxEvent> watch({key}) => fakeWatch(key: key);

  @override
  Future<void> flush() async {
    ensureOpen();
    flushCount++;
  }

  @override
  Future<void> compact() async {
    ensureOpen();
    compactCount++;
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> deleteFromDisk() async {
    wasDeletedFromDisk = true;
    isClosed = true;
    store.clear();
  }
}
