/// @docImport '/src/box/list/list_box.dart';
/// @docImport 'lazy_single_value_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/core/box_provider.dart';
import '/src/core/engine/eager_crud_engine.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/observer/box_observer.dart';
import 'single_value_slot_key.dart';

/// A typed, fpdart-first façade over an **eager** hive box holding exactly one [T] value.
///
/// The lone-setting / token / config-blob scenario: no keys on the surface, just the value.
/// Internally it sits under one fixed slot, the same slot the 0.0.x single managers used, so
/// that data reads in place. Eager means the value lives in memory once the box is open: reads
/// are synchronous and disk-free, writes are lazy [Task]s that only touch disk when run.
/// Acquisition is [open] alone: there is no public constructor, so holding a [SingleValueBox]
/// *implies* its box is open. Prefer [LazySingleValueBox] when the value is large or read
/// rarely.
///
/// The functional contract, shared by every façade in this package:
///
/// - absence is [Option], never `null` and never a sentinel;
/// - effects are [Task]s: nothing runs until `.run()`, so they compose before they execute;
/// - [clear] is the one unset (no separate delete; nothing else to delete).
///
/// Storing a collection as [T] re-opens the disk-reification trap this package exists to guard
/// (post-restart reads reify as `List<dynamic>`); reach for [ListBox] instead.
///
/// Throw taxonomy: whatever the engine itself throws for (operating on a closed box, an
/// unregistered adapter) surfaces unwrapped inside the returned [Task] when it runs. [close]
/// and [deleteFromDisk] are terminal: the handle stays unusable afterwards, and reacquisition
/// means a new [open].
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class SingleValueBox<T extends Object>._({required final EagerCrudEngine<T> _engine}) {
  /// The box name: the correlation handle observers receive with every event.
  String get name => _engine.name;

  /// `1` when a value is stored, `0` when not; a single-value box never holds more.
  int get length => _engine.length;

  /// Whether no value is stored right now.
  bool get isEmpty => _engine.isEmpty;

  /// Whether a value is stored right now.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// Reads the value synchronously from memory: `Some` when set, `None` when never set (or
  /// cleared).
  Option<T> get() => _engine.get(singleValueRawSlotKey, singleValueSlotKey);

  /// Reads the value, falling back to [fallback] when absent. Sugar over [get].
  T getOr(T fallback) => _engine.getOr(singleValueRawSlotKey, singleValueSlotKey, fallback);

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
  /// axes. No replay: pair with [get] for the current value.
  Stream<Option<T>> watch() => _engine
      .watchRaw(key: singleValueRawSlotKey)
      .map(
        (event) => event.deleted ? const None() : Some(_engine.decodeStored(event.value as Object)),
      );

  /// Flushes pending writes to disk when run. Maintenance, not a data event: observers only
  /// hear failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, not a data event: observers only hear
  /// failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. **Terminal**: every later operation surfaces hive's own
  /// already-closed error, and reacquisition means a new [open].
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. **Terminal**, like [close].
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();

  /// Opens the box named [name] and wires a [SingleValueBox] around it, as a lazy [Task]:
  /// nothing touches disk until `.run()`.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or
  /// `Hive.initFlutter()`) plus adapter registration. [cipher], [keyComparator],
  /// [compactionStrategy], and [crashRecovery] pass through to hive_ce untouched. [observer]
  /// hears every event of this box, starting with the open itself; a failed open dispatches an
  /// operation error and rethrows inside the task.
  static Task<SingleValueBox<T>> open<T extends Object>(
    String name, {
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) => Task(() async {
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
      return SingleValueBox<T>._(
        engine: EagerCrudEngine<T>(
          box: box,
          valueCodec: IdentityValueCodec<T>(),
          observer: observer,
        ),
      );
    } on Object catch (error, stackTrace) {
      observer?.onOperationError(name, 'open', error, stackTrace);
      rethrow;
    }
  });
}

/// Testing seam: wires a [SingleValueBox] around an already-open (or fake) [box] instead of
/// going through the real provider, so unit suites drive the façade against in-memory doubles.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show`
/// keeps it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
SingleValueBox<T> singleValueBoxAround<T extends Object>(
  Box<Object?> box, {
  BoxObserver? observer,
}) => SingleValueBox<T>._(
  // Explicit type arguments on purpose; see CODESTYLE #type-safety.
  engine: EagerCrudEngine<T>(box: box, valueCodec: IdentityValueCodec<T>(), observer: observer),
);
