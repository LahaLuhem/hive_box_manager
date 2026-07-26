/// @docImport '/src/box/keyed/keyed_box.dart';
/// @docImport 'lazy_list_box.dart';
library;

import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/eager_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/collection_cast_value_codec.dart';
import '/src/event/typed_box_event.dart';
import '/src/observer/box_observer.dart';
import 'list_edits.dart';

/// A typed, fpdart-first façade over an **eager** hive box storing a `List` of [T] per [K] key.
///
/// This variant exists because of a real engine limitation: hive reifies a collection of an
/// **adapter-registered** type from disk as `List<dynamic>`, so a naive `Box<List<Person>>` opens
/// fine and then throws on the first post-restart read. Here the element type is restored with a
/// cast at the read boundary instead, and `dynamic` never reaches this surface.
///
/// Lists of primitives are the exception: hive specialises those, so a `List<String>` does read
/// back as `List<String>` and a hand-rolled cast would survive. The benchmark's list-box lane
/// measures both axes and the cast costs the same either way, so this surface does not branch on
/// it: about 200 ns per [get] plus about 2.3 ns per element actually iterated. The view allocates
/// nothing (measured RSS matches a hand-rolled cast exactly), so the per-element part is the type
/// check, not a copy.
///
/// List semantics only: order-preserving, duplicates allowed. Sets, maps, and nested
/// collections of custom types are deliberately out (the outer cast could not fix inner
/// reification); store flat lists, or model richer shapes as adapter-registered value types.
///
/// The aliasing contract, both directions:
///
/// - **inward**: [put], [putAll], and [update]'s returns are materialised into private copies,
///   so mutating your original collection afterwards never reaches the box
///   (and lazy iterables become the plain lists hive requires at write time).
/// - **outward**: every list this box hands you ([get], [getOr], [values], [update]'s return, watch-event payloads) is an unmodifiable zero-copy view; absence is still [Option], and an
///   empty stored list reads `Some(empty)`, never `None`.
///
/// Everything else matches [KeyedBox]: eager reads are synchronous and disk-free, effects are lazy
/// [Task]s, keys go through a [KeyCodec] (`int` / `String` default to identity codecs), the write
/// path gates raw keys with a synchronous [ArgumentError], engine failures surface unwrapped inside
/// tasks, and [close] / [deleteFromDisk] are terminal.
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class ListBox<T extends Object, K extends Object> {
  final EagerCrudEngine<List<T>> _engine;
  final KeyCodec<K> _codec;

  /// Wiring is internal: acquisition goes through [open] (tests use the seam below).
  ListBox._({required this._engine, required this._codec});

  /// Encodes [key] for the engine, which admits only encoded keys.
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name: the correlation handle observers receive with every event.
  String get name => _engine.name;

  /// Number of stored keys (not summed elements); keys always live in memory, so this is free.
  int get length => _engine.length;

  /// Whether the box holds no keys.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one key.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded through the box's [KeyCodec] as they are iterated.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// The stored lists, each an unmodifiable view, decoded as they are iterated. Dispatches one read-all
  /// event at call time.
  Iterable<List<T>> get values => _engine.values;

  /// Reads the list under [key] synchronously from memory: `Some` of an unmodifiable zero-copy view
  /// when present (`Some(empty)` for a stored empty list), `None` when the key is absent.
  Option<List<T>> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// Reads the list under [key], falling back to an empty list when absent: the natural default for
  /// a collection, so there is no fallback parameter. Absent and stored-empty read the same here.
  /// Use [get] to distinguish them.
  List<T> getOr(K key) => _engine.get(_rawKeyFor(key), key).getOrElse(List.empty);

  /// Whether [key] is stored right now.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Stores [values] under [key] when run, materialised into a private fixed-length copy:
  /// hive rejects non-`List` iterables at write time, and the copy keeps your original collection yours.
  /// Throws a synchronous [ArgumentError] at the call site when the encoded key leaves hive's raw domain,
  /// exactly like [KeyedBox.put].
  Task<Unit> put(K key, Iterable<T> values) =>
      _engine.put(_rawKeyFor(key), key, materialisedCopyOf(values));

  /// Stores every entry of [entries] in one batch when run, each list materialised as in [put].
  /// All keys are encoded and gated at call time, so a bad key means nothing gets written.
  Task<Unit> putAll(Map<K, Iterable<T>> entries) => _engine.putAll(
    // Lazy: the engine's own pass consumes this, so the batch is materialised once, not twice.
    entries.entries.map(
      (entry) => MapEntry(_rawKeyFor(entry.key), materialisedCopyOf(entry.value)),
    ),
  );

  /// Rewrites the list under [key] through [update] when run, mirroring [Map.update]: an absent key
  /// is seeded by [ifAbsent], and with no [ifAbsent] the task fails with an [ArgumentError] at run time.
  ///
  /// [update] receives the unmodifiable view (build and return a new list. In-place mutation is impossible by construction),
  /// returns are materialised into private copies like [put], and the task's result is the unmodifiable
  /// view of the new list. A read-modify-write: O(n) in the stored list.
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
  /// Sugar over [update]: a read-modify-write, O(n) in the stored list.
  Task<Unit> add(K key, T value) => _engine
      // Fresh lists by construction, so the sugar paths skip the defensive copy.
      .update(_rawKeyFor(key), key, (values) => [...values, value], ifAbsent: () => [value])
      .map((_) => unit);

  /// Appends every element of [values] to the list under [key] when run; an absent key becomes a copy
  /// of [values]. Sugar over [update]: a read-modify-write, O(n) in the stored list.
  Task<Unit> addAll(K key, Iterable<T> values) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (stored) => [...stored, ...values],
        ifAbsent: () => materialisedCopyOf(values),
      )
      .map((_) => unit);

  /// Removes the **first occurrence** of [value] from the list under [key] when run, mirroring `List.remove`:
  /// an absent key or an absent element is a no-op, and removing the last element leaves an empty
  /// list stored (`Some(empty)`), never a deleted key. A read-modify-write, O(n) in the stored list.
  Task<Unit> remove(K key, T value) => Task(() async {
    // Encoded once, reused by both halves of the read-modify-write.
    final rawKey = _rawKeyFor(key);
    final storedValues = _engine.get(rawKey, key).toNullable();
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

  /// Typed change stream; pass [key] to watch one key only. Event payloads carry the same unmodifiable
  /// views reads do, non-null even on deletes (the eager promise).
  Stream<TypedBoxEvent<List<T>, K>> watch({K? key}) => _engine
      .watchRaw(key: key == null ? null : _rawKeyFor(key))
      .map(
        (event) => TypedBoxEvent<List<T>, K>(
          key: _codec.decode(event.key as Object),
          value: _engine.decodeStored(event.value as Object),
          deleted: event.deleted,
        ),
      );

  /// Flushes pending writes to disk when run. Maintenance, not a data event: observers only hear failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, not a data event: observers only hear failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. **Terminal**: every later operation surfaces hive's own already-closed
  /// error, and reacquisition means a new [open].
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. **Terminal**, like [close].
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();

  /// Opens the box named [name] and wires an [ListBox] around it, as a lazy [Task]: nothing
  /// touches disk until `.run()`.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or `Hive.initFlutter()`)
  /// plus adapter registration for the **element** type [T]. [codec] defaults by key type
  /// (`int` / `String` identity codecs; any other [K] without an explicit codec fails an assert synchronously at wiring time).
  /// [cipher], [keyComparator], [compactionStrategy], and [crashRecovery] pass through to hive_ce
  /// untouched. [observer] hears every event of this box, starting with the open itself.
  static Task<ListBox<T, K>> open<T extends Object, K extends Object>(
    String name, {
    KeyCodec<K>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) {
    final keyCodec = resolveKeyCodec<K>(codec);

    return Task(() async {
      try {
        final box = await BoxProvider().openEagerBox(
          name,
          cipher: cipher,
          keyComparator: keyComparator,
          compactionStrategy: compactionStrategy,
          crashRecovery: crashRecovery,
        );
        observer?.onOpened(name);

        // Type arguments stay explicit through this wiring (CODESTYLE #type-safety).
        return ListBox<T, K>._(
          engine: EagerCrudEngine<List<T>>(
            box: box,
            valueCodec: CollectionCastValueCodec<T>(),
            observer: observer,
          ),
          codec: keyCodec,
        );
      } on Object catch (error, stackTrace) {
        observer?.onOperationError(name, 'open', error, stackTrace);
        rethrow;
      }
    });
  }
}

/// Testing seam: wires an [ListBox] around an already-open (or fake) [box] instead of going through
/// the real provider, so unit suites drive the façade against in-memory doubles.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show` keeps
/// it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
ListBox<T, K> listBoxAround<T extends Object, K extends Object>(
  Box<Object?> box, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => ListBox<T, K>._(
  // Explicit type arguments on purpose; see CODESTYLE #type-safety.
  engine: EagerCrudEngine<List<T>>(
    box: box,
    valueCodec: CollectionCastValueCodec<T>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
);
