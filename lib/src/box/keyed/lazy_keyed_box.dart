/// @docImport 'keyed_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/event/lazy_typed_box_event.dart';
import '/src/observer/box_observer.dart';

/// A typed, fpdart-first façade over a **lazy** hive box of [T] values keyed by [K].
///
/// Lazy means hive holds only the keystore in memory and fetches each value off disk when asked, so
/// reads are effects too: [get] hands back a [TaskOption], [getOr] and [values] hand back [Task]s. Reach
/// for [KeyedBox] when the box is read often and fits in RAM comfortably.
///
/// Building one touches nothing. The box opens on the first effect that runs, once even if several race
/// for it, and a failed open is forgotten so the next run tries again. [ensureInitialised] is that same
/// warm-up if you would rather do it up front.
///
/// The sync inspectors ([length], [isEmpty], [isNotEmpty], [keys], [contains]) need that keystore, so
/// before the first effect they throw a [StateError] telling you what to run. That is the one sync carve-out
/// on this surface.
///
/// A key hive cannot store safely throws an [ArgumentError] at the call site, before you get a [Task]
/// back. Whatever hive itself objects to, a failed open included, comes out of the [Task] when it runs.
/// [close] and [deleteFromDisk] are terminal.
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class LazyKeyedBox<T extends Object, K extends Object>._({
  required final LazyCrudEngine<T> _engine,
  required final KeyCodec<K> _codec,
}) {
  /// Wires up a box that opens on first use. Building it touches nothing, so `Hive.init(path)` and your
  /// adapters only need to be done before the first effect runs.
  ///
  /// [codec] defaults by key type: `int` and `String` get the identity codecs, and any other [K] without
  /// one trips an assert while wiring. [cipher], [keyComparator], [compactionStrategy] and [crashRecovery]
  /// go straight through to hive_ce at the eventual open. [observer] hears everything this box does,
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
         // Explicit type arguments: a bare `const IdentityValueCodec()` can't mention T, so inference
         // quietly picks `Never` and the first put blows up at run time.
         engine: LazyCrudEngine<T>(
           boxName: name,
           openBox: () => BoxProvider().openLazyBox(
             name,
             cipher: cipher,
             keyComparator: keyComparator,
             compactionStrategy: compactionStrategy,
             crashRecovery: crashRecovery,
           ),
           valueCodec: IdentityValueCodec<T>(),
           observer: observer,
         ),
         codec: resolveKeyCodec<K>(codec),
       );

  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name, there before the box ever opens. Observers hear it with every event.
  String get name => _engine.name;

  /// How many entries are stored. Throws a [StateError] before the first open.
  int get length => _engine.length;

  /// Whether the box holds no entries. Throws a [StateError] before the first open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry. Throws a [StateError] before the first open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded as they are iterated. Throws a [StateError] before the first open.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// Every stored value when run, each read off disk into one list, so by the time it completes the
  /// reads are done. One read-all event per run.
  Task<List<T>> get values => _engine.values(_codec.decode);

  /// Opens the box when run. Any effect would do it anyway, this just gets it out of the way.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether [key] is stored right now. Throws a [StateError] before the first open.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Reads [key] from disk when run: `Some` when present, `None` when absent.
  TaskOption<T> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// Reads [key] from disk when run, falling back to [fallback] when absent.
  Task<T> getOr(K key, T fallback) => _engine.getOr(_rawKeyFor(key), key, fallback);

  /// Writes [value] under [key] when run.
  Task<Unit> put(K key, T value) => _engine.put(_rawKeyFor(key), key, value);

  /// Writes every entry of [entries] in one batch when run. Keys are checked up front, so one bad key
  /// means nothing is written at all.
  Task<Unit> putAll(Map<K, T> entries) => _engine.putAll(
    // Lazy on purpose: the engine's own pass consumes it, so the batch gets built once, not twice.
    entries.entries.map((entry) => MapEntry(_rawKeyFor(entry.key), entry.value)),
  );

  /// Writes every value in [values] when run, each under the key [key] extracts from it.
  ///
  /// Handy when values carry their own id, and cheaper than [putAll] since no `Map` gets built on the
  /// way.
  ///
  /// Use [putAll] when the key doesn't come from the value, which is most of the time.
  ///
  /// 2 values landing on the same key trips an assert in development, and in release the later one
  /// wins.
  Task<Unit> putAllBy(Iterable<T> values, {required K Function(T value) key}) =>
      _engine.putAll(values.map((value) => MapEntry(_rawKeyFor(key(value)), value)));

  /// Rewrites [key] through [update] when run and returns the new value, same deal as [Map.update].
  /// An absent key is seeded by [ifAbsent], and without one the task fails with an [ArgumentError].
  Task<T> update(K key, T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update(_rawKeyFor(key), key, update, ifAbsent: ifAbsent);

  /// Deletes [key] when run. Deleting something that isn't there is a no-op.
  Task<Unit> delete(K key) => _engine.delete(_rawKeyFor(key), key);

  /// Deletes every key in [keys] in one batch when run. Observers hear one event per key.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Built once: the batch needs raw keys, the hooks need semantic ones.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll([for (final key in keyList) _rawKeyFor(key)], keyList);
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream. Pass [key] to watch one key only, the one nullable on this surface and a toggle
  /// you pass rather than a value you get back.
  ///
  /// Writes carry `Some` and deletes carry `None`, since a lazy box keeps no values around to attach.
  Stream<LazyTypedBoxEvent<T, K>> watch({K? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key)).map((event) {
        final semanticKey = _codec.decode(event.key as Object);

        return LazyTypedBoxEvent<T, K>(
          key: semanticKey,
          value: Option.fromNullable(event.value as Object?)
              .map((storedValue) => _engine.decodeStored(storedValue, semanticKey)),
        );
      });

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

/// Testing seam: wraps a [LazyKeyedBox] around [openBox] rather than the real provider, so unit suites
/// can use in-memory doubles and scripted opens.
///
/// Not exported, so only suites importing this file directly can see it.
@visibleForTesting
LazyKeyedBox<T, K> lazyKeyedBoxAround<T extends Object, K extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => LazyKeyedBox<T, K>._(
  // Explicit type arguments on purpose, see the note inside the unnamed constructor.
  engine: LazyCrudEngine<T>(
    boxName: name,
    openBox: openBox,
    valueCodec: IdentityValueCodec<T>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
);
