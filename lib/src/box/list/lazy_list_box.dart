/// @docImport '/src/box/keyed/lazy_keyed_box.dart';
/// @docImport 'list_box.dart';
library;

import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/collection_cast_value_codec.dart';
import '/src/event/lazy_typed_box_event.dart';
import '/src/observer/box_observer.dart';
import 'list_edits.dart';

/// A typed, fpdart-first façade over a **lazy** hive box storing a `List` of [T] per [K] key.
///
/// The collection variant on the lazy axis: hive keeps only the keystore in memory and reads each
/// list from disk on demand, so reads are effects ([get] returns a [TaskOption], [getOr] and [values]
/// return [Task]s). The variant exists because hive reifies collections from disk as `List<dynamic>`
/// whatever the write-side element type; the element type is restored with a cast at the read boundary,
/// and `dynamic` never reaches this surface. Prefer [ListBox] for small, hot collections.
///
/// List semantics only: order-preserving, duplicates allowed. Sets, maps, and nested collections of
/// custom types are deliberately out (the outer cast could not fix inner reification).
///
/// The aliasing contract, both directions:
///
/// - **inward**: [put], [putAll], and [update]'s returns are materialised into private copies, so
///   mutating your original collection afterwards never reaches the box
///   (and lazy iterables become the plain lists hive requires at write time).
/// - **outward**: every list this box hands you is an unmodifiable view; absence is still [Option],
///   and an empty stored list reads `Some(empty)`, never `None`.
///
/// Everything else matches [LazyKeyedBox]: synchronous construction with single-flight auto-open
/// (plus [ensureInitialised]), the sync inspectors ([length], [isEmpty], [isNotEmpty], [keys], [contains])
/// throwing [StateError] before the first open, the synchronous [ArgumentError] key gate on writes,
/// engine failures unwrapped inside tasks, and terminal [close] / [deleteFromDisk] with the pre-first-use
/// close no-op.
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class LazyListBox<T extends Object, K extends Object>._({
  required final LazyCrudEngine<List<T>> _engine,
  required final KeyCodec<K> _codec,
}) {
  /// Wires a box that opens single-flight on first use; construction itself touches nothing.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or `Hive.initFlutter()`)
  /// plus adapter registration for the **element** type [T], before the first effect runs. [codec]
  /// defaults by key type (`int` / `String` identity codecs. Any other [K] without an explicit codec
  /// fails an assert at wiring time). [cipher], [keyComparator], [compactionStrategy], and [crashRecovery]
  /// pass through to hive_ce untouched at the eventual open. [observer] hears every event of this box,
  /// starting with that open.
  new(
    String name, {
    KeyCodec<K>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) : this._(
         // Type arguments stay explicit through this wiring (CODESTYLE #type-safety).
         engine: LazyCrudEngine<List<T>>(
           boxName: name,
           openBox: () => BoxProvider().openLazyBox(
             name,
             cipher: cipher,
             keyComparator: keyComparator,
             compactionStrategy: compactionStrategy,
             crashRecovery: crashRecovery,
           ),
           valueCodec: CollectionCastValueCodec<T>(),
           observer: observer,
         ),
         codec: resolveKeyCodec<K>(codec),
       );

  /// Encodes [key] for the engine, which admits only encoded keys.
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name, available before the box ever opens: the observer correlation handle.
  String get name => _engine.name;

  /// Number of stored keys (not summed elements). Sync carve-out: throws [StateError] before the first open.
  int get length => _engine.length;

  /// Whether the box holds no keys. Sync carve-out: throws [StateError] before the first open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one key. Sync carve-out: throws [StateError] before the first open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded through the box's [KeyCodec] as they are iterated. Sync carve-out:
  /// throws [StateError] before the first open.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// Every stored list when run, each read from disk, materialised, and handed over as an unmodifiable
  /// view. Dispatches one read-all event per run.
  Task<List<List<T>>> get values => _engine.values(_codec.decode);

  /// Warms the box up compositionally when run; any effect performs the same open implicitly.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether [key] is stored right now. Sync carve-out: throws [StateError] before the first open.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Reads the list under [key] from disk when run: `Some` of an unmodifiable view when present
  /// (`Some(empty)` for a stored empty list), `None` when the key is absent.
  TaskOption<List<T>> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// Reads the list under [key] from disk when run, falling back to an empty list when absent: the
  /// natural default for a collection, so there is no fallback parameter. Absent and stored-empty
  /// read the same here. Use [get] to distinguish them.
  Task<List<T>> getOr(K key) => _engine.get(_rawKeyFor(key), key).getOrElse(List.empty);

  /// Stores [values] under [key] when run, materialised into a private fixed-length copy: hive rejects
  /// non-`List` iterables at write time, and the copy keeps your original collection yours. Throws a
  /// synchronous [ArgumentError] at the call site when the encoded key leaves hive's raw domain, exactly
  /// like [LazyKeyedBox.put].
  Task<Unit> put(K key, Iterable<T> values) =>
      _engine.put(_rawKeyFor(key), key, materialisedCopyOf(values));

  /// Stores every entry of [entries] in one batch when run, each list materialised as in [put].
  /// All keys are encoded and gated at call time, so a bad key means nothing gets written.
  Task<Unit> putAll(Map<K, Iterable<T>> entries) => _engine.putAll(
    // Lazy: the engine's own pass consumes this, so the batch is materialised once.
    entries.entries.map(
      (entry) => MapEntry(_rawKeyFor(entry.key), materialisedCopyOf(entry.value)),
    ),
  );

  /// Rewrites the list under [key] through [update] when run, mirroring [Map.update]: an absent key
  /// is seeded by [ifAbsent], and with no [ifAbsent] the task fails with an [ArgumentError] at run time.
  ///
  /// [update] receives the unmodifiable view (build and return a new list), returns are materialised
  /// into private copies like [put], and the task's result is the unmodifiable view of the new list.
  /// A read-modify-write: one disk read plus O(n) in the stored list.
  Task<List<T>> update(
    K key,
    List<T> Function(List<T> values) update, {
    List<T> Function()? ifAbsent,
  }) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (values) => materialisedCopyOf(update(values)),
        ifAbsent: ifAbsent == null ? null : () => materialisedCopyOf(ifAbsent()),
      )
      .map(UnmodifiableListView.new);

  /// Appends [value] to the list under [key] when run; an absent key becomes `[value]` (multimap-natural).
  /// Sugar over [update]: a read-modify-write, one disk read plus O(n).
  Task<Unit> add(K key, T value) => _engine
      // Fresh lists by construction, so the sugar paths skip the defensive copy.
      .update(_rawKeyFor(key), key, (values) => [...values, value], ifAbsent: () => [value])
      .map((_) => unit);

  /// Appends every element of [values] to the list under [key] when run; an absent key becomes a copy
  /// of [values]. Sugar over [update]: a read-modify-write, one disk read plus O(n).
  Task<Unit> addAll(K key, Iterable<T> values) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (stored) => [...stored, ...values],
        ifAbsent: () => materialisedCopyOf(values),
      )
      .map((_) => unit);

  /// Removes the **first occurrence** of [value] from the list under [key] when run, mirroring `List.remove`:
  /// an absent key or an absent element is a no-op, and removing the last element leaves an empty list
  /// stored (`Some(empty)`), never a deleted key. A read-modify-write: one disk read plus O(n) in
  /// the stored list.
  Task<Unit> remove(K key, T value) => Task(() async {
    // Encoded once, reused by both halves of the read-modify-write.
    final rawKey = _rawKeyFor(key);
    final storedValues = (await _engine.get(rawKey, key).run()).toNullable();
    if (storedValues == null) return unit;

    final index = storedValues.indexOf(value);
    if (index < 0) return unit;

    await _engine.put(rawKey, key, copyWithoutIndex(storedValues, index)).run();

    return unit;
  });

  /// Deletes [key] and its whole list when run; deleting an absent key is hive's documented no-op.
  Task<Unit> delete(K key) => _engine.delete(_rawKeyFor(key), key);

  /// Deletes every key in [keys] in one batch when run; observers hear one event per key.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Materialised once: the batch needs raw keys, the hooks need semantic ones.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll([for (final key in keyList) _rawKeyFor(key)], keyList);
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream; pass [key] to watch one key only. Subscribing auto-opens like any effect.
  /// Write events carry `Some` of the same unmodifiable views reads do; deletes carry `None`
  /// (the lazy engine holds no values), with [LazyTypedBoxEvent.deleted] derived from that.
  Stream<LazyTypedBoxEvent<List<T>, K>> watch({K? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key)).map((event) {
        final semanticKey = _codec.decode(event.key as Object);

        return LazyTypedBoxEvent<List<T>, K>(
          key: semanticKey,
          value: Option.fromNullable(event.value as Object?)
              .map((storedValue) => _engine.decodeStored(storedValue, semanticKey)),
        );
      });

  /// Writes every value in [values] when run, grouped into one stored list per key [key] extracts.
  ///
  /// The list-shaped counterpart to the keyed families' `putAllBy`: a flat iterable in, one list per
  /// distinct key out, elements in encounter order. **Replaces** the list at each key rather than
  /// appending, matching [putAll]; use [addAll] to extend what is already stored.
  ///
  /// Grouping cannot stay lazy the way [putAll] does, because every value has to be seen before any
  /// one list is final. The grouped lists are built here and never escape, so they skip the defensive
  /// copy [put] makes.
  ///
  /// Reach for [putAll] when the key is not derivable from the element, or when a key needs an **empty**
  /// list: grouping can never produce one, and stored-empty is a distinct state from absent on this surface.
  Task<Unit> putAllGrouped(Iterable<T> values, {required K Function(T value) key}) {
    final grouped = <K, List<T>>{};
    for (final value in values) {
      grouped.putIfAbsent(key(value), () => <T>[]).add(value);
    }

    return _engine.putAll(
      grouped.entries.map((entry) => MapEntry(_rawKeyFor(entry.key), entry.value)),
    );
  }

  /// Flushes pending writes to disk when run. Maintenance, not a data event: observers only hear failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, not a data event: observers only hear failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. **Terminal**: every later operation surfaces hive's already-closed error,
  /// and reacquisition means a new instance. Before first use this is a no-op that never opens the
  /// box (observers still hear the close), yet the handle still turns terminal.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. **Terminal**, like [close]. Before first use this still opens
  /// then deletes: it must reach storage.
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();
}

/// Testing seam: wires a [LazyListBox] around [openBox] instead of the real provider, so unit suites
/// drive the façade against in-memory doubles and scripted opens.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show` keeps
/// it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
LazyListBox<T, K> lazyListBoxAround<T extends Object, K extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => LazyListBox<T, K>._(
  // Explicit type arguments on purpose; see CODESTYLE #type-safety.
  engine: LazyCrudEngine<List<T>>(
    boxName: name,
    openBox: openBox,
    valueCodec: CollectionCastValueCodec<T>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
);
