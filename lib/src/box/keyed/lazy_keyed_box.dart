/// @docImport 'keyed_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/event/lazy_typed_box_event.dart';
import '/src/observer/box_observer.dart';

/// A typed, fpdart-first façade over a **lazy** hive box of [T] values keyed by [K].
///
/// Lazy means hive keeps only the keystore in memory and reads each value from disk on demand,
/// so every read is an effect: [get] returns a [TaskOption], [getOr] and [values] return
/// [Task]s. Construction is synchronous and touches nothing; the box opens **single-flight**
/// when the first effect runs (concurrent first effects share one open, and a failed open resets
/// the memo so the next run retries), with [ensureInitialised] exposing that warm-up
/// compositionally. Prefer [KeyedBox] for hot, value-heavy-read boxes that fit comfortably in
/// RAM.
///
/// The functional contract, shared by every façade in this package:
///
/// - absence is [Option], never `null` and never a sentinel;
/// - effects are [Task]s: nothing runs until `.run()`, so they compose before they execute;
/// - keys go through a [KeyCodec]; `int` / `String` keys default to the identity codecs.
///
/// The sync inspectors ([length], [isEmpty], [isNotEmpty], [keys], [contains]) need the
/// keystore, which exists only once the box has opened: before the first effect (or
/// [ensureInitialised]) they throw a [StateError] naming the fix. This is the surface's one
/// deliberate sync carve-out.
///
/// Throw taxonomy: write-path methods throw a **synchronous** [ArgumentError] at the call site
/// when the encoded key leaves hive's raw domain (release-mode hive_ce corrupts silently there);
/// whatever the engine itself throws for surfaces unwrapped inside the returned [Task] when it
/// runs. [close] and [deleteFromDisk] are terminal; closing before first use never opens the box
/// yet still leaves the handle terminal.
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class LazyKeyedBox<T extends Object, K extends Object> {
  final LazyCrudEngine<T, K> _engine;

  /// Wires a box that opens single-flight on first use; construction itself touches nothing.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or
  /// `Hive.initFlutter()`) plus adapter registration, before the first effect runs.
  ///
  /// [codec] defaults by key type: `int` / `String` resolve to the identity codecs, and any
  /// other [K] without an explicit codec fails an assert at wiring time. [cipher],
  /// [keyComparator], [compactionStrategy], and [crashRecovery] pass through to hive_ce
  /// untouched at the eventual open. [observer] hears every event of this box, starting with
  /// that open; a failed open dispatches an operation error and rethrows inside the failing
  /// effect's task.
  LazyKeyedBox(
    String name, {
    KeyCodec<K>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) : this._(
         // Type arguments stay explicit through this wiring: a bare `const IdentityValueCodec()`
         // cannot mention T, so inference silently instantiates it as `Never`, which covariance
         // accepts statically and the first put trips over at run time.
         engine: LazyCrudEngine<T, K>(
           boxName: name,
           openBox: () => BoxProvider().openLazyBox(
             name,
             cipher: cipher,
             keyComparator: keyComparator,
             compactionStrategy: compactionStrategy,
             crashRecovery: crashRecovery,
           ),
           keyCodec: resolveKeyCodec<K>(codec),
           valueCodec: IdentityValueCodec<T>(),
           observer: observer,
         ),
       );

  /// Wiring is internal: consumers construct via the unnamed constructor (tests use the seam
  /// below).
  LazyKeyedBox._({required this._engine});

  /// The box name, available before the box ever opens: the observer correlation handle.
  String get name => _engine.name;

  /// Number of stored entries. Sync carve-out: throws [StateError] before the first open.
  int get length => _engine.length;

  /// Whether the box holds no entries. Sync carve-out: throws [StateError] before the first
  /// open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry. Sync carve-out: throws [StateError] before the
  /// first open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded through the box's [KeyCodec] as they are iterated. Sync carve-out:
  /// throws [StateError] before the first open.
  Iterable<K> get keys => _engine.keys;

  /// Every stored value when run, each read from disk and materialised into one list:
  /// completion means every disk read already happened. Dispatches one read-all event per run.
  Task<List<T>> get values => _engine.values();

  /// Warms the box up compositionally when run; any effect performs the same open implicitly.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether [key] is stored right now. Sync carve-out: throws [StateError] before the first
  /// open.
  bool contains(K key) => _engine.contains(key);

  /// Reads [key] from disk when run: `Some` when present, `None` when absent.
  TaskOption<T> get(K key) => _engine.get(key);

  /// Reads [key] from disk when run, falling back to [fallback] when absent. Sugar over [get].
  Task<T> getOr(K key, T fallback) => _engine.getOr(key, fallback);

  /// Writes [value] under [key] when run.
  ///
  /// Throws a synchronous [ArgumentError] at the call site, before the [Task] even exists, when
  /// the encoded key leaves hive's raw domain (an int outside `0..0xFFFFFFFF`, a String over 255
  /// UTF-8 bytes): exactly the keys release-mode hive_ce accepts and then corrupts on. Engine
  /// failures, including a failed auto-open, surface inside the task.
  Task<Unit> put(K key, T value) => _engine.put(key, value);

  /// Writes every entry of [entries] in one batch when run. All keys are encoded and gated at
  /// call time, so a bad key means nothing gets written; same throw taxonomy as [put].
  Task<Unit> putAll(Map<K, T> entries) => _engine.putAll(entries);

  /// Rewrites [key] through [update] when run and returns the new value, mirroring [Map.update]:
  /// an absent [key] is seeded by [ifAbsent], and with no [ifAbsent] the task fails with an
  /// [ArgumentError] at run time. The call-site key gate applies as in [put].
  Task<T> update(K key, T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update(key, update, ifAbsent: ifAbsent);

  /// Deletes [key] when run; deleting an absent key is hive's documented no-op. Deletes are not
  /// gated: a key this box never admitted cannot reach disk this way.
  Task<Unit> delete(K key) => _engine.delete(key);

  /// Deletes every key in [keys] in one batch when run; observers hear one event per key.
  Task<Unit> deleteAll(Iterable<K> keys) => _engine.deleteAll(keys);

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream; pass [key] to watch one key only (the surface's one blessed nullable:
  /// a toggle you pass, never a value you receive). Subscribing auto-opens like any effect.
  ///
  /// Writes carry `Some`, deletes carry `None`: a lazy box retains no values in memory, so the
  /// engine has nothing to attach on deletes (pinned behaviour); [LazyTypedBoxEvent.deleted] is
  /// derived from exactly that.
  Stream<LazyTypedBoxEvent<T, K>> watch({K? key}) => _engine.watch(key: key);

  /// Flushes pending writes to disk when run. Maintenance, not a data event: observers only hear
  /// failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, not a data event: observers only hear
  /// failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. **Terminal**: every later operation surfaces hive's already-closed
  /// error, and reacquisition means a new instance. Before first use this is a no-op that never
  /// opens the box (observers still hear the close), yet the handle still turns terminal.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. **Terminal**, like [close]. Before first use this still
  /// opens then deletes: it must reach storage.
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();
}

/// Testing seam: wires a [LazyKeyedBox] around [openBox] instead of the real provider, so unit
/// suites drive the façade against in-memory doubles and scripted opens.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show`
/// keeps it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
LazyKeyedBox<T, K> lazyKeyedBoxAround<T extends Object, K extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => LazyKeyedBox<T, K>._(
  // Explicit type arguments on purpose; see the note inside the unnamed constructor.
  engine: LazyCrudEngine<T, K>(
    boxName: name,
    openBox: openBox,
    keyCodec: resolveKeyCodec<K>(codec),
    valueCodec: IdentityValueCodec<T>(),
    observer: observer,
  ),
);
