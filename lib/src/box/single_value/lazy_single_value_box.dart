/// @docImport '/src/box/list/lazy_list_box.dart';
/// @docImport 'single_value_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/observer/box_observer.dart';
import 'single_value_slot_key.dart';

/// A typed, fpdart-first façade over a **lazy** hive box holding exactly one [T] value.
///
/// The single-value scenario with the lazy axis's cost model: hive keeps only the keystore in
/// memory and reads the value from disk on demand, so reads are effects ([get] returns a
/// [TaskOption], [getOr] a [Task]). Construction is synchronous and touches nothing; the box
/// opens **single-flight** when the first effect runs, with [ensureInitialised] exposing that
/// warm-up compositionally. Internally the value sits under the same fixed slot the 0.0.x
/// single managers used, so that data reads in place. Prefer [SingleValueBox] when the value is
/// small and read often.
///
/// The functional contract, shared by every façade in this package:
///
/// - absence is [Option], never `null` and never a sentinel;
/// - effects are [Task]s: nothing runs until `.run()`, so they compose before they execute;
/// - [clear] is the one unset (no separate delete; nothing else to delete).
///
/// The sync inspectors ([length], [isEmpty], [isNotEmpty]) need the keystore, which exists only
/// once the box has opened: before the first effect (or [ensureInitialised]) they throw a
/// [StateError] naming the fix. Storing a collection as [T] re-opens the disk-reification trap
/// this package exists to guard; reach for [LazyListBox] instead.
///
/// Throw taxonomy: whatever the engine itself throws for surfaces unwrapped inside the returned
/// [Task] when it runs. [close] and [deleteFromDisk] are terminal; closing before first use
/// never opens the box yet still leaves the handle terminal.
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class LazySingleValueBox<T extends Object>._({required final LazyCrudEngine<T> _engine}) {
  /// Wires a box that opens single-flight on first use; construction itself touches nothing.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or
  /// `Hive.initFlutter()`) plus adapter registration, before the first effect runs. [cipher],
  /// [keyComparator], [compactionStrategy], and [crashRecovery] pass through to hive_ce
  /// untouched at the eventual open. [observer] hears every event of this box, starting with
  /// that open; a failed open dispatches an operation error and rethrows inside the failing
  /// effect's task.
  new(
    String name, {
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) : this._(
         // Type arguments stay explicit through this wiring (CODESTYLE #type-safety).
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
       );

  /// The box name, available before the box ever opens: the observer correlation handle.
  String get name => _engine.name;

  /// `1` when a value is stored, `0` when not. Sync carve-out: throws [StateError] before the
  /// first open.
  int get length => _engine.length;

  /// Whether no value is stored right now. Sync carve-out: throws [StateError] before the first
  /// open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether a value is stored right now. Sync carve-out: throws [StateError] before the first
  /// open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// Warms the box up compositionally when run; any effect performs the same open implicitly.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Reads the value from disk when run: `Some` when set, `None` when never set (or cleared).
  TaskOption<T> get() => _engine.get(singleValueRawSlotKey, singleValueSlotKey);

  /// Reads the value from disk when run, falling back to [fallback] when absent. Sugar over
  /// [get].
  Task<T> getOr(T fallback) => _engine.getOr(singleValueRawSlotKey, singleValueSlotKey, fallback);

  /// Stores [value] when run, replacing whatever was there.
  Task<Unit> set(T value) => _engine.put(singleValueRawSlotKey, singleValueSlotKey, value);

  /// Rewrites the value through [update] when run and returns the new value, mirroring
  /// [Map.update] on the internal slot: an absent value is seeded by [ifAbsent], and with no
  /// [ifAbsent] the task fails with an [ArgumentError] at run time.
  Task<T> update(T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update(singleValueRawSlotKey, singleValueSlotKey, update, ifAbsent: ifAbsent);

  /// Unsets the value when run; the next [get] reads `None`. Observers hear a clear.
  Task<Unit> clear() => _engine.clear();

  /// The value's change stream: `Some` on every [set], `None` on [clear]. Same shape on both
  /// axes (a lazy delete event carries no value, which maps to `None` anyway). Subscribing
  /// auto-opens like any effect; no replay, so pair with [get] for the current value.
  Stream<Option<T>> watch() => _engine
      .watchRaw(key: singleValueRawSlotKey)
      .map((event) => Option.fromNullable(event.value as Object?).map(_engine.decodeStored));

  /// Flushes pending writes to disk when run. Maintenance, not a data event: observers only
  /// hear failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, not a data event: observers only hear
  /// failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. **Terminal**: every later operation surfaces hive's
  /// already-closed error, and reacquisition means a new instance. Before first use this is a
  /// no-op that never opens the box (observers still hear the close), yet the handle still
  /// turns terminal.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. **Terminal**, like [close]. Before first use this
  /// still opens then deletes: it must reach storage.
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();
}

/// Testing seam: wires a [LazySingleValueBox] around [openBox] instead of the real provider, so
/// unit suites drive the façade against in-memory doubles and scripted opens.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show`
/// keeps it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
LazySingleValueBox<T> lazySingleValueBoxAround<T extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  BoxObserver? observer,
}) => LazySingleValueBox<T>._(
  // Explicit type arguments on purpose; see CODESTYLE #type-safety.
  engine: LazyCrudEngine<T>(
    boxName: name,
    openBox: openBox,
    valueCodec: IdentityValueCodec<T>(),
    observer: observer,
  ),
);
