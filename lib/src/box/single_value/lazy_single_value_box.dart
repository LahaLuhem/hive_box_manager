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
/// The single-value case on the lazy axis, so the value comes off disk when asked and reads are effects.
/// Building one touches nothing, and the box opens on the first effect that runs. It sits under the
/// same fixed slot the 0.0.x single managers used, so that data still reads. Reach for [SingleValueBox]
/// when the value is small and read often.
///
/// [clear] is the only way to unset it. There is no separate delete, since there is nothing else to
/// delete.
///
/// The sync inspectors ([length], [isEmpty], [isNotEmpty]) need the keystore, so before the first effect
/// they throw a [StateError] telling you what to run. Don't store a collection as [T], that walks straight
/// back into the reification trap [LazyListBox] exists to handle.
///
/// Whatever hive objects to comes out of the [Task] when it runs. [close] and [deleteFromDisk] are terminal,
/// and closing before first use won't open the box just to close it.
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class LazySingleValueBox<T extends Object>._({required final LazyCrudEngine<T> _engine}) {
  /// Wires up a box that opens on first use. Building it touches nothing.
  ///
  /// Engine setup is still hive_ce's job, so `Hive.init(path)` and your adapters come first, before
  /// the first effect runs. [cipher], [keyComparator], [compactionStrategy] and [crashRecovery] go straight
  /// through at the eventual open. [observer] hears everything this box does, starting with that open.
  new(
    String name, {
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) : this._(
         // Explicit type arguments on purpose, see CODESTYLE #type-safety.
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

  /// The box name, there before the box ever opens. Observers hear it with every event.
  String get name => _engine.name;

  /// `1` when a value is stored, `0` when not. Sync carve-out: throws [StateError] before the first
  /// open.
  int get length => _engine.length;

  /// Whether no value is stored right now. Sync carve-out: throws [StateError] before the first open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether a value is stored right now. Sync carve-out: throws [StateError] before the first open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// Opens the box when run. Any effect would do it anyway, this just gets it out of the way.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Reads the value from disk when run: `Some` when set, `None` when never set (or cleared).
  TaskOption<T> get() => _engine.get(singleValueRawSlotKey, singleValueSlotKey);

  /// Reads the value from disk when run, falling back to [fallback] when absent. Sugar over [get].
  Task<T> getOr(T fallback) => _engine.getOr(singleValueRawSlotKey, singleValueSlotKey, fallback);

  /// Stores [value] when run, replacing whatever was there.
  Task<Unit> set(T value) => _engine.put(singleValueRawSlotKey, singleValueSlotKey, value);

  /// Rewrites the value through [update] when run and returns the new value, mirroring [Map.update]
  /// on the internal slot: an absent value is seeded by [ifAbsent], and with no [ifAbsent] the task
  /// fails with an [ArgumentError] at run time.
  Task<T> update(T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update(singleValueRawSlotKey, singleValueSlotKey, update, ifAbsent: ifAbsent);

  /// Unsets the value when run, so the next [get] reads `None`. Observers hear a clear.
  Task<Unit> clear() => _engine.clear();

  /// The value's change stream: `Some` on every [set], `None` on [clear]. There is no replay, so pair
  /// it with [get] if you need the current value.
  Stream<Option<T>> watch() => _engine
      .watchRaw(key: singleValueRawSlotKey)
      .map(
        (event) =>
            Option.fromNullable(event.value as Object?)
                .map((storedValue) => _engine.decodeStored(storedValue, singleValueSlotKey)),
      );

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

/// Testing seam: wires a [LazySingleValueBox] around [openBox] instead of the real provider, so unit
/// suites drive the façade against in-memory doubles and scripted opens.
///
/// Not exported, so only suites importing this file directly can see it.
@visibleForTesting
LazySingleValueBox<T> lazySingleValueBoxAround<T extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  BoxObserver? observer,
}) => LazySingleValueBox<T>._(
  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  engine: LazyCrudEngine<T>(
    boxName: name,
    openBox: openBox,
    valueCodec: IdentityValueCodec<T>(),
    observer: observer,
  ),
);
