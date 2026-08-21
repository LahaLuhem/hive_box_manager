/// @docImport 'lazy_keyed_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/eager_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/event/typed_box_event.dart';
import '/src/observer/box_observer.dart';

/// A typed, fpdart-first façade over an **eager** hive box of [T] values keyed by [K].
///
/// Eager means every value lives in memory once the box is open, so reads are synchronous and disk-free.
/// Writes and lifecycle effects are lazy [Task]s that only touch disk when run.
/// Acquisition is [open] alone: there is no public constructor, so holding a [KeyedBox] *implies* its
/// box is open and sync reads are always legal. Prefer [LazyKeyedBox] when values are large or read sparsely.
///
/// The functional contract, shared by every façade in this package:
///
/// - absence is [Option], never `null` and never a sentinel;
/// - effects are [Task]s: nothing runs until `.run()`, so they compose before they execute;
/// - keys go through a [KeyCodec]; `int` / `String` keys default to the identity codecs.
///
/// Throw taxonomy: write-path methods throw a **synchronous** [ArgumentError] at the call site when
/// the encoded key leaves hive's raw domain (release-mode hive_ce corrupts silently there). Whatever
/// the engine itself throws for (operating on a closed box, an unregistered adapter) surfaces unwrapped
/// inside the returned [Task] when it runs. [close] and [deleteFromDisk] are terminal: the handle
/// stays unusable afterwards, and reacquisition means a new [open].
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class KeyedBox<T extends Object, K extends Object>._({
  required final EagerCrudEngine<T> _engine,
  required final KeyCodec<K> _codec,
}) {
  /// Encodes [key] for the engine, which admits only encoded keys.
  // Inlined: sits on the read path, in front of an engine get that is itself inlined.
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name: the correlation handle observers receive with every event.
  String get name => _engine.name;

  /// Number of stored entries; keys always live in memory, so this is free.
  int get length => _engine.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded through the box's [KeyCodec] as they are iterated.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// The stored values, served from the in-memory cache and decoded as they are iterated.
  /// Dispatches one read-all event at call time.
  Iterable<T> get values => _engine.values;

  /// Reads [key] synchronously from memory: `Some` when present, `None` when absent.
  // Inlined into callers; see the engine's get for why.
  @pragma('vm:prefer-inline')
  Option<T> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// Reads [key], falling back to [fallback] when absent. Sugar over [get].
  T getOr(K key, T fallback) => _engine.getOr(_rawKeyFor(key), key, fallback);

  /// Whether [key] is stored right now.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Writes [value] under [key] when run.
  ///
  /// Throws a synchronous [ArgumentError] at the call site, before the [Task] even exists, when the
  /// encoded key leaves hive's raw domain (an int outside `0..0xFFFFFFFF`, a String over 255 UTF-8 bytes):
  /// exactly the keys release-mode hive_ce accepts and then corrupts on. Engine failures surface inside
  /// the task.
  Task<Unit> put(K key, T value) => _engine.put(_rawKeyFor(key), key, value);

  /// Writes every entry of [entries] in one batch when run. All keys are encoded and gated at call
  /// time, so a bad key means nothing gets written; same throw taxonomy as [put].
  Task<Unit> putAll(Map<K, T> entries) => _engine.putAll(
    // Lazy: the engine's own pass consumes this, so the batch is materialised once, not twice.
    entries.entries.map((entry) => MapEntry(_rawKeyFor(entry.key), entry.value)),
  );

  /// Writes every value in [values] when run, each under the key [key] extracts from it.
  ///
  /// Sugar over [putAll] for values that carry their own key. No intermediate `Map` is built at all:
  /// [key] is applied inside the same pass that encodes and gates, so this is the cheaper of the two
  /// as well as the shorter.
  ///
  /// Reach for [putAll] when the key is not derivable from the value, which is most of the time:
  /// primitives, values without an id, or keys that come from somewhere else entirely.
  ///
  /// Two values yielding the same key trips an assert in development; in release the later one wins.
  /// Same throw taxonomy as [putAll] otherwise, gate included.
  Task<Unit> putAllBy(Iterable<T> values, {required K Function(T value) key}) =>
      _engine.putAll(values.map((value) => MapEntry(_rawKeyFor(key(value)), value)));

  /// Rewrites [key] through [update] when run and returns the new value, mirroring [Map.update]:
  /// an absent [key] is seeded by [ifAbsent], and with no [ifAbsent] the task fails with an
  /// [ArgumentError] at run time. The call-site key gate applies as in [put].
  Task<T> update(K key, T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update(_rawKeyFor(key), key, update, ifAbsent: ifAbsent);

  /// Deletes [key] when run; deleting an absent key is hive's documented no-op. Deletes are not gated:
  /// a key this box never admitted cannot reach disk this way.
  Task<Unit> delete(K key) => _engine.delete(_rawKeyFor(key), key);

  /// Deletes every key in [keys] in one batch when run; observers hear one event per key.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Materialised once: the batch needs raw keys, the hooks need semantic ones.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll([for (final key in keyList) _rawKeyFor(key)], keyList);
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream; pass [key] to watch one key only. That parameter is the surface's one blessed
  /// nullable: a toggle you pass, never a value you receive.
  ///
  /// Events carry a **non-null** [TypedBoxEvent.value] even for deletes: eager hive_ce delivers the
  /// just-deleted value from its cache (pinned behaviour), so consumers never null-check.
  Stream<TypedBoxEvent<T, K>> watch({K? key}) => _engine
      .watchRaw(key: key == null ? null : _rawKeyFor(key))
      .map(
        (event) => TypedBoxEvent<T, K>(
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

  /// Opens the box named [name] and wires a [KeyedBox] around it, as a lazy [Task]: nothing touches
  /// disk until `.run()`.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or `Hive.initFlutter()`)
  /// plus adapter registration. Opening a name that is already open joins hive's same underlying box
  /// (idempotent open); opening it as a different box kind fails with hive's own error inside the task.
  ///
  /// [codec] defaults by key type: `int` / `String` resolve to the identity codecs, and any other [K]
  /// without an explicit codec fails an assert synchronously at wiring time, before the task exists.
  /// [cipher], [keyComparator], [compactionStrategy], and [crashRecovery] pass through to hive_ce
  /// untouched. [observer] hears every event of this box, starting with the open itself. A failed
  /// open dispatches an operation error and rethrows inside the task.
  static Task<KeyedBox<T, K>> open<T extends Object, K extends Object>(
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

        // Type arguments stay explicit through this wiring: a bare `const IdentityValueCodec()` cannot
        // mention T, so inference silently instantiates it (and, chained, the engine) as `Never`,
        // which covariance accepts statically and the first put trips over at run time.
        return KeyedBox<T, K>._(
          engine: EagerCrudEngine<T>(
            box: box,
            valueCodec: IdentityValueCodec<T>(),
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

/// Testing seam: wires a [KeyedBox] around an already-open (or fake) [box] instead of going through
/// the real provider, so unit suites drive the façade against in-memory doubles.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show` keeps
/// it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
KeyedBox<T, K> keyedBoxAround<T extends Object, K extends Object>(
  Box<Object?> box, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => KeyedBox<T, K>._(
  // Explicit type arguments on purpose; see the note inside `open`.
  engine: EagerCrudEngine<T>(box: box, valueCodec: IdentityValueCodec<T>(), observer: observer),
  codec: resolveKeyCodec<K>(codec),
);
