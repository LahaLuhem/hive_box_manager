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
/// This variant exists because hive reads a collection of an adapter-registered type back as `List<dynamic>`,
/// so a plain `Box<List<Person>>` opens fine and then throws on the first read after a restart. Here
/// the element type gets restored with a cast at the read boundary, and `dynamic` never reaches you.
///
/// Lists of primitives are the exception, since hive specialises those and a `List<String>` does come
/// back as one. The cast costs the same either way, so this surface doesn't branch on it (`benchmark/list_box_bench.dart`).
/// The view allocates nothing, so what you pay per element is the type check, not a copy.
///
/// Lists only, so order is kept and duplicates are fine. Sets, maps and nested collections of custom
/// types are out, because the outer cast can't fix the inner reification. Store flat lists, or model
/// richer shapes as their own adapter-registered types.
///
/// The aliasing contract, both directions:
///
/// - **inward**: [put], [putAll] and [update]'s returns get copied, so mutating your own collection
///   afterwards never reaches the box.
/// - **outward**: every list you get back is an unmodifiable view over the stored one. An empty stored
///   list reads `Some(empty)`, never `None`.
///
/// Everything else works like [KeyedBox].
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class ListBox<T extends Object, K extends Object>._({
  required final EagerCrudEngine<List<T>> _engine,
  required final KeyCodec<K> _codec,
}) {
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name. Observers hear it with every event.
  String get name => _engine.name;

  /// How many keys are stored, not how many elements. Keys live in memory, so this is free.
  int get length => _engine.length;

  /// Whether the box holds no keys.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one key.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded through the box's [KeyCodec] as they are iterated.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// The stored lists, each an unmodifiable view, decoded as they are iterated. Dispatches one read-all
  /// event at call time.
  Iterable<List<T>> get values => _engine.values(_codec.decode);

  /// Reads the list under [key] synchronously from memory: `Some` of an unmodifiable zero-copy view
  /// when present (`Some(empty)` for a stored empty list), `None` when the key is absent.
  Option<List<T>> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// Reads the list under [key], falling back to an empty one. That is the obvious default for a collection,
  /// so there is no fallback parameter. Absent and stored-empty look the same here, use [get] to tell
  /// them apart.
  List<T> getOr(K key) => _engine.get(_rawKeyFor(key), key).getOrElse(List.empty);

  /// Whether [key] is stored right now.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Stores [values] under [key] when run, copied first so your own collection stays yours. Rejects
  /// an unstorable key on the spot, like [KeyedBox.put].
  Task<Unit> put(K key, Iterable<T> values) =>
      _engine.put(_rawKeyFor(key), key, materialisedCopyOf(values));

  /// Stores every entry of [entries] in one batch when run, each list materialised as in [put]. All
  /// keys are encoded and gated at call time, so a bad key means nothing gets written.
  Task<Unit> putAll(Map<K, Iterable<T>> entries) => _engine.putAll(
    // Lazy on purpose: the engine's own pass consumes it, so the batch gets built once, not twice.
    entries.entries.map(
      (entry) => MapEntry(_rawKeyFor(entry.key), materialisedCopyOf(entry.value)),
    ),
  );

  /// Rewrites the list under [key] through [update] when run, mirroring [Map.update]: an absent key
  /// is seeded by [ifAbsent], and with no [ifAbsent] the task fails with an [ArgumentError] at run time.
  ///
  /// [update] gets the unmodifiable view, so build and return a new list rather than trying to mutate
  /// it. A read-modify-write, O(n) in the stored list.
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

  /// Appends [value] to the list under [key] when run. A key that isn't there yet becomes `[value]`.
  /// A read-modify-write, O(n) in the stored list.
  Task<Unit> add(K key, T value) => _engine
      // Fresh lists by construction, so the sugar paths skip the defensive copy.
      .update(_rawKeyFor(key), key, (values) => [...values, value], ifAbsent: () => [value])
      .map((_) => unit);

  /// Appends every element of [values] to the list under [key] when run. A key that isn't there yet
  /// becomes a copy of [values]. A read-modify-write, O(n) in the stored list.
  Task<Unit> addAll(K key, Iterable<T> values) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (stored) => [...stored, ...values],
        ifAbsent: () => materialisedCopyOf(values),
      )
      .map((_) => unit);

  /// Removes the first [value] from the list under [key] when run, same as `List.remove`. A missing
  /// key or element is a no-op, and taking the last element out leaves an empty list rather than deleting
  /// the key. O(n) in the stored list.
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

  /// Deletes [key] and its whole list when run. Deleting something that isn't there is a no-op.
  Task<Unit> delete(K key) => _engine.delete(_rawKeyFor(key), key);

  /// Deletes every key in [keys] in one batch when run. Observers hear one event per key.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Built once: the batch needs raw keys, the hooks need semantic ones.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll([for (final key in keyList) _rawKeyFor(key)], keyList);
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream. Pass [key] to watch one key only. Payloads carry the same unmodifiable views
  /// reads hand you, and deletes still carry a value.
  Stream<TypedBoxEvent<List<T>, K>> watch({K? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key)).map((event) {
        final semanticKey = _codec.decode(event.key as Object);

        return TypedBoxEvent<List<T>, K>(
          key: semanticKey,
          value: _engine.decodeStored(event.value as Object, semanticKey),
          deleted: event.deleted,
        );
      });

  /// Writes every value in [values] when run, grouped into one stored list per key [key] extracts.
  ///
  /// The list-shaped counterpart to the keyed families' `putAllBy`: a flat iterable in, one list per
  /// distinct key out, elements in encounter order. **Replaces** the list at each key rather than appending,
  /// same as [putAll]. Use [addAll] to extend what is already there.
  ///
  /// Grouping cannot stay lazy the way [putAll] does, because every value has to be seen before any
  /// one list is final. The grouped lists are built here and never escape, so they skip the defensive
  /// copy [put] makes.
  ///
  /// Reach for [putAll] when the key is not derivable from the element, or when a key needs an **empty**
  /// list: grouping can never produce one, and stored-empty is a distinct state from absent on this
  /// surface.
  Task<Unit> putAllGrouped(Iterable<T> values, {required K Function(T value) key}) {
    final grouped = <K, List<T>>{};
    for (final value in values) {
      grouped.putIfAbsent(key(value), () => <T>[]).add(value);
    }

    return _engine.putAll(
      grouped.entries.map((entry) => MapEntry(_rawKeyFor(entry.key), entry.value)),
    );
  }

  /// Flushes pending writes to disk when run. Maintenance, so observers only hear about failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, so observers only hear about failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. Terminal, see the class doc.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. Terminal, like [close].
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();

  /// Opens the box named [name] and wires an [ListBox] around it, as a lazy [Task]: nothing touches
  /// disk until `.run()`.
  ///
  /// Engine setup is still hive_ce's job, and the adapter you register is for the **element** type [T].
  /// [codec] defaults by key type, and any other [K] without one trips an assert while wiring. [cipher],
  /// [keyComparator], [compactionStrategy] and [crashRecovery] go straight through. [observer] hears
  /// everything this box does, starting with the open.
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

        // Explicit type arguments on purpose, see CODESTYLE #type-safety.
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
/// Not exported, so only suites importing this file directly can see it.
@visibleForTesting
ListBox<T, K> listBoxAround<T extends Object, K extends Object>(
  Box<Object?> box, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => ListBox<T, K>._(
  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  engine: EagerCrudEngine<List<T>>(
    box: box,
    valueCodec: CollectionCastValueCodec<T>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
);
