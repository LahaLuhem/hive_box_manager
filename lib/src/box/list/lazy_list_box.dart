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
/// The collection variant on the lazy axis, so hive holds only the keystore and fetches each list off
/// disk when asked. It exists because hive reads collections back as `List<dynamic>` whatever you wrote,
/// so the element type gets restored with a cast at the read boundary. Reach for [ListBox] when the
/// lists are small and read often.
///
/// List semantics only: order-preserving, duplicates allowed. Sets, maps, and nested collections of
/// custom types are deliberately out (the outer cast could not fix inner reification).
///
/// The aliasing contract, both directions:
///
/// - **inward**: [put], [putAll] and [update]'s returns get copied, so mutating your own collection
///   afterwards never reaches the box.
/// - **outward**: every list you get back is an unmodifiable view. An empty stored list reads `Some(empty)`,
///   never `None`.
///
/// Open-on-first-use, the sync inspectors, the key check and the terminal [close] all work like [LazyKeyedBox].
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class LazyListBox<T extends Object, K extends Object>._({
  required final LazyCrudEngine<List<T>> _engine,
  required final KeyCodec<K> _codec,
}) {
  /// Wires up a box that opens on first use. Building it touches nothing.
  ///
  /// Engine setup is still hive_ce's job, and the adapter you register is for the **element** type [T].
  /// [codec] defaults by key type, and any other [K] without one trips an assert while wiring. [cipher],
  /// [keyComparator], [compactionStrategy] and [crashRecovery] go straight through at the eventual open.
  /// [observer] hears everything this box does, starting with that open.
  new(
    String name, {
    KeyCodec<K>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) : this._(
         // Explicit type arguments on purpose, see CODESTYLE #type-safety.
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

  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name, there before the box ever opens. Observers hear it with every event.
  String get name => _engine.name;

  /// Number of stored keys (not summed elements). Sync carve-out: throws [StateError] before the first
  /// open.
  int get length => _engine.length;

  /// Whether the box holds no keys. Sync carve-out: throws [StateError] before the first open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one key. Sync carve-out: throws [StateError] before the first open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded as they are iterated. Throws a [StateError] before the first open.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// Every stored list when run, each read from disk, materialised, and handed over as an unmodifiable
  /// view. Dispatches one read-all event per run.
  Task<List<List<T>>> get values => _engine.values(_codec.decode);

  /// Opens the box when run. Any effect would do it anyway, this just gets it out of the way.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether [key] is stored right now. Throws a [StateError] before the first open.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Reads the list under [key] from disk when run: `Some` of an unmodifiable view when present (`Some(empty)`
  /// for a stored empty list), `None` when the key is absent.
  TaskOption<List<T>> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// Reads the list under [key] off disk when run, falling back to an empty one. That is the obvious
  /// default for a collection, so there is no fallback parameter. Absent and stored-empty look the same
  /// here, use [get] to tell them apart.
  Task<List<T>> getOr(K key) => _engine.get(_rawKeyFor(key), key).getOrElse(List.empty);

  /// Stores [values] under [key] when run, copied first so your own collection stays yours. Rejects
  /// an unstorable key on the spot, like [LazyKeyedBox.put].
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
  /// it. A read-modify-write, one disk read plus O(n) in the stored list.
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
  /// A read-modify-write, one disk read plus O(n).
  Task<Unit> add(K key, T value) => _engine
      // Fresh lists by construction, so the sugar paths skip the defensive copy.
      .update(_rawKeyFor(key), key, (values) => [...values, value], ifAbsent: () => [value])
      .map((_) => unit);

  /// Appends every element of [values] to the list under [key] when run. A key that isn't there yet
  /// becomes a copy of [values]. A read-modify-write, one disk read plus O(n).
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
  /// the key. One disk read plus O(n) in the stored list.
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

  /// Typed change stream. Pass [key] to watch one key only. Writes carry `Some` of the same unmodifiable
  /// views reads hand you, and deletes carry `None`.
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

  /// Closes the box when run. Terminal, see the class doc. Before first use it won't open the box just
  /// to close it, but the handle is spent all the same.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. Terminal, like [close]. This one does open first, since it
  /// has to reach storage.
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();
}

/// Testing seam: wires a [LazyListBox] around [openBox] instead of the real provider, so unit suites
/// drive the façade against in-memory doubles and scripted opens.
///
/// Not exported, so only suites importing this file directly can see it.
@visibleForTesting
LazyListBox<T, K> lazyListBoxAround<T extends Object, K extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => LazyListBox<T, K>._(
  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  engine: LazyCrudEngine<List<T>>(
    boxName: name,
    openBox: openBox,
    valueCodec: CollectionCastValueCodec<T>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
);
