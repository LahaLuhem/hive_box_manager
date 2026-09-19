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
/// For the lone setting, the token, the config blob: no keys on the surface, just the value. It sits
/// under one fixed slot internally, the same one the 0.0.x single managers used, so that data still
/// reads. Eager means the value is in memory once the box is open, so reads are synchronous and writes
/// are [Task]s. Reach for [LazySingleValueBox] when the value is big or rarely read.
///
/// [clear] is the only way to unset it. There is no separate delete, since there is nothing else to
/// delete.
///
/// Don't store a collection as [T], that walks straight back into the reification trap [ListBox] exists
/// to handle.
///
/// Whatever hive objects to (a closed box, a missing adapter) comes out of the [Task] when it runs.
/// [close] and [deleteFromDisk] are terminal: the handle is spent, and getting back in means a fresh
/// [open].
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class SingleValueBox<T extends Object>._({required final EagerCrudEngine<T> _engine}) {
  /// The box name. Observers hear it with every event.
  String get name => _engine.name;

  /// `1` when a value is stored, `0` when not. A single-value box never holds more.
  int get length => _engine.length;

  /// Whether no value is stored right now.
  bool get isEmpty => _engine.isEmpty;

  /// Whether a value is stored right now.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// Reads the value synchronously from memory: `Some` when set, `None` when never set (or cleared).
  Option<T> get() => _engine.get(singleValueRawSlotKey, singleValueSlotKey);

  /// Reads the value, falling back to [fallback] when absent. Sugar over [get].
  T getOr(T fallback) => _engine.getOr(singleValueRawSlotKey, singleValueSlotKey, fallback);

  /// Stores [value] when run, replacing whatever was there.
  Task<Unit> set(T value) => _engine.put(singleValueRawSlotKey, singleValueSlotKey, value);

  /// Rewrites the value through [update] when run and returns the new value, mirroring [Map.update]
  /// on the internal slot: an absent value is seeded by [ifAbsent], and with no [ifAbsent] the task
  /// fails with an [ArgumentError] at run time.
  Task<T> update(T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update(singleValueRawSlotKey, singleValueSlotKey, update, ifAbsent: ifAbsent);

  /// Unsets the value when run, so the next [get] reads `None`. Observers hear a clear.
  Task<Unit> clear() => _engine.clear();

  /// The value's change stream: `Some` on every [set], `None` on [clear]. Same shape on both axes. No
  /// replay: pair with [get] for the current value.
  Stream<Option<T>> watch() => _engine
      .watchRaw(key: singleValueRawSlotKey)
      .map(
        (event) => event.deleted
            ? const None()
            : Some(_engine.decodeStored(event.value as Object, singleValueSlotKey)),
      );

  /// Flushes pending writes to disk when run. Maintenance, so observers only hear about failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, so observers only hear about failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. Terminal, see the class doc.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. Terminal, like [close].
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();

  /// Opens the box named [name] and wires a [SingleValueBox] around it, as a lazy [Task]: nothing touches
  /// disk until `.run()`.
  ///
  /// Engine setup is still hive_ce's job, so `Hive.init(path)` and your adapters come first. [cipher],
  /// [keyComparator], [compactionStrategy] and [crashRecovery] go straight through. [observer] hears
  /// everything this box does, starting with the open.
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

      // Explicit type arguments on purpose, see CODESTYLE #type-safety.
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

/// Testing seam: wires a [SingleValueBox] around an already-open (or fake) [box] instead of going through
/// the real provider, so unit suites drive the façade against in-memory doubles.
///
/// Not exported, so only suites importing this file directly can see it.
@visibleForTesting
SingleValueBox<T> singleValueBoxAround<T extends Object>(
  Box<Object?> box, {
  BoxObserver? observer,
}) => SingleValueBox<T>._(
  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  engine: EagerCrudEngine<T>(box: box, valueCodec: IdentityValueCodec<T>(), observer: observer),
);
