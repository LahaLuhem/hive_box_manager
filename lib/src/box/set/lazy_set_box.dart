/// @docImport 'set_box.dart';
library;

import 'package:collection/collection.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/set_cast_value_codec.dart';
import '/src/event/lazy_typed_box_event.dart';
import '/src/observer/box_observer.dart';
import 'element_id.dart';

/// A **lazy** box holding a `Set` of [T] per [K] key, read off disk when asked.
///
/// Same rules as [SetBox]: pass `idOf` unless the elements are strings, numbers, bools or enums, and
/// every write leaves one element per id.
///
/// It opens on the first effect. Until then the sync inspectors ([length], [isEmpty], [isNotEmpty],
/// [keys], [contains]) throw a [StateError].
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class LazySetBox<T extends Object, K extends Object>._({
  required final LazyCrudEngine<Set<T>> _engine,
  required final KeyCodec<K> _codec,
  required final Object Function(T element) _idOf,
}) {
  /// Wires up a box that opens on first use, so `Hive.init` and your adapters only need to be ready
  /// by the first effect. Leaving out [codec] or [idOf] where the type needs one trips an assert.
  new(
    String name, {
    KeyCodec<K>? codec,
    Object Function(T element)? idOf,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) : this._(
         // Explicit type arguments on purpose, see CODESTYLE #type-safety.
         engine: LazyCrudEngine<Set<T>>(
           boxName: name,
           openBox: () => BoxProvider().openLazyBox(
             name,
             cipher: cipher,
             keyComparator: keyComparator,
             compactionStrategy: compactionStrategy,
             crashRecovery: crashRecovery,
           ),
           valueCodec: SetCastValueCodec<T>(),
           observer: observer,
         ),
         codec: resolveKeyCodec<K>(codec),
         idOf: resolveIdOf<T>(idOf),
       );

  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name, there before the box opens.
  String get name => _engine.name;

  /// How many keys are stored, not how many elements.
  int get length => _engine.length;

  /// Whether the box holds no keys.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one key.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// Every stored set when run.
  Task<List<Set<T>>> get values => _engine.values(_codec.decode);

  /// Opens the box when run, if you'd rather not wait for the first effect.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether [key] is stored.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// The set under [key] when run, or `None` when it's absent.
  TaskOption<Set<T>> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// The set under [key] when run, or an empty one. Use [get] to tell absent from stored-empty.
  Task<Set<T>> getOr(K key) =>
      _engine.get(_rawKeyFor(key), key).getOrElse(() => UnmodifiableSetView(<T>{}));

  /// Stores [values] under [key] when run.
  Task<Unit> put(K key, Iterable<T> values) =>
      _engine.put(_rawKeyFor(key), key, dedupedById(values, _idOf));

  /// [put] for every entry of [entries], in one batch.
  Task<Unit> putAll(Map<K, Iterable<T>> entries) => _engine.putAll(
    // Left lazy so the engine builds the batch in one pass.
    entries.entries.map(
      (entry) => MapEntry(_rawKeyFor(entry.key), dedupedById(entry.value, _idOf)),
    ),
  );

  /// Rewrites the set under [key] through [update] when run, like [Map.update].
  Task<Set<T>> update(
    K key,
    Set<T> Function(Set<T> values) update, {
    Set<T> Function()? ifAbsent,
  }) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (values) => dedupedById(update(values), _idOf),
        ifAbsent: ifAbsent == null ? null : () => dedupedById(ifAbsent(), _idOf),
      )
      .map(UnmodifiableSetView.new);

  /// Adds [value] to the set under [key] when run. If its id is already there, the stored one stays.
  Task<Unit> add(K key, T value) => addAll(key, [value]);

  /// [add] for each of [values].
  Task<Unit> addAll(K key, Iterable<T> values) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (stored) => dedupedById(stored.followedBy(values), _idOf),
        ifAbsent: () => dedupedById(values, _idOf),
      )
      .map((_) => unit);

  /// Like [add], but a stored element with the same id gets replaced, in place.
  Task<Unit> upsert(K key, T value) => upsertAll(key, [value]);

  /// [upsert] for each of [values].
  Task<Unit> upsertAll(K key, Iterable<T> values) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (stored) => upsertedById(stored, values, _idOf),
        ifAbsent: () => dedupedById(values, _idOf),
      )
      .map((_) => unit);

  /// Removes the element with [value]'s id when run. The key stays, even once its set is empty.
  Task<Unit> remove(K key, T value) => Task(() async {
    final rawKey = _rawKeyFor(key);
    final storedValues = (await _engine.get(rawKey, key).run()).toNullable();
    if (storedValues == null) return unit;

    final removedId = _idOf(value);
    bool isRemoved(T element) => _idOf(element) == removedId;
    if (storedValues.none(isRemoved)) return unit;

    await _engine.put(rawKey, key, dedupedById(storedValues.whereNot(isRemoved), _idOf)).run();

    return unit;
  });

  /// Deletes [key] and its set when run.
  Task<Unit> delete(K key) => _engine.delete(_rawKeyFor(key), key);

  /// Deletes every key in [keys] in one batch when run.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Copied so a lazy [keys] isn't walked twice.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll(keyList.map(_rawKeyFor).toList(growable: false), keyList);
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed changes, for [key] alone if given. Deletes carry `None`, since a lazy box keeps no values.
  Stream<LazyTypedBoxEvent<Set<T>, K>> watch({K? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key)).map((event) {
        final semanticKey = _codec.decode(event.key as Object);

        return LazyTypedBoxEvent<Set<T>, K>(
          key: semanticKey,
          value: Option.fromNullable(event.value as Object?)
              .map((storedValue) => _engine.decodeStored(storedValue, semanticKey)),
        );
      });

  /// Writes [values] when run, one set per key [keyOf] gives, replacing what's there.
  Task<Unit> putAllGrouped(Iterable<T> values, {required K Function(T value) keyOf}) =>
      _engine.putAll(
        values
            .groupListsBy(keyOf)
            .entries
            .map((entry) => MapEntry(_rawKeyFor(entry.key), dedupedById(entry.value, _idOf))),
      );

  /// Flushes pending writes to disk when run.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. This handle is done after that, even if it never opened.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run, opening it first if needed. This handle is done after that.
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();
}

/// Testing seam: a [LazySetBox] around [openBox] instead of the real provider. Not exported.
@visibleForTesting
LazySetBox<T, K> lazySetBoxAround<T extends Object, K extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  KeyCodec<K>? codec,
  Object Function(T element)? idOf,
  BoxObserver? observer,
}) => LazySetBox<T, K>._(
  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  engine: LazyCrudEngine<Set<T>>(
    boxName: name,
    openBox: openBox,
    valueCodec: SetCastValueCodec<T>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
  idOf: resolveIdOf<T>(idOf),
);
