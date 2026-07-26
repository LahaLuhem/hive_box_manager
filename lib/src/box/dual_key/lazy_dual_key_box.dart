/// @docImport '/src/box/keyed/lazy_keyed_box.dart';
/// @docImport '/src/codec/dual/packed_int_dual_codec.dart';
/// @docImport '/src/codec/dual/string_composite_dual_codec.dart';
/// @docImport 'dual_key_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/dual/dual_key_codec.dart';
import '/src/codec/dual/dual_key_codec_adapter.dart';
import '/src/codec/dual/dual_key_codec_resolution.dart';
import '/src/codec/key/key_codec.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/event/lazy_typed_box_event.dart';
import '/src/observer/box_observer.dart';
import '/src/query/scan_query_index.dart';

/// A typed, fpdart-first façade over a **lazy** hive box addressed by a two-part composite key,
/// with reverse queries by either part folded in.
///
/// The dual-key surface on the lazy axis: hive keeps only the keystore in memory and reads each
/// value from disk on demand, so reads are effects ([get] returns a [TaskOption], [getOr],
/// [values], and both queries return [Task]s). Operations take the parts separately or as
/// `(K1, K2)` records where a whole key travels. Both parts round-trip through one
/// [DualKeyCodec]: `(int, int)` parts default to [StringCompositeDualCodec], and
/// [PackedIntDualCodec] is the measured performance opt-in with its 16-bit-per-part ceiling.
/// Prefer [DualKeyBox] for hot, value-heavy-read boxes that fit comfortably in RAM.
///
/// [queryByPrimary] / [queryBySecondary] answer "everything at this part" with a plain,
/// possibly-empty list inside a [Task], never an `Option`. The strategy is an honest **O(K)
/// scan** over the live key set; matches are fetched from disk in parallel, and observers hear
/// one read per matched key. Queries auto-open like any effect.
///
/// Everything else matches [LazyKeyedBox]: synchronous construction with single-flight
/// auto-open (plus [ensureInitialised]), the sync inspectors ([length], [isEmpty],
/// [isNotEmpty], [keys], [contains]) throwing [StateError] before the first open, the
/// synchronous [ArgumentError] key gate on writes, engine failures unwrapped inside tasks, and
/// terminal [close] / [deleteFromDisk] with the pre-first-use close no-op.
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class LazyDualKeyBox<T extends Object, K1 extends Object, K2 extends Object> {
  final LazyCrudEngine<T> _engine;
  final DualKeyCodec<K1, K2> _dualCodec;

  /// On death row, exactly as in `DualKeyBox`: the ~350 ns per op issue #14 removes, kept one
  /// checkpoint longer so this refactor carries no measurable delta.
  final KeyCodec<(K1, K2)> _adapter;

  /// Wires a box that opens single-flight on first use; construction itself touches nothing.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or
  /// `Hive.initFlutter()`) plus adapter registration, before the first effect runs. [codec]
  /// defaults by part types: `(int, int)` resolves to [StringCompositeDualCodec], and any other
  /// pair without an explicit codec fails an assert at wiring time. [cipher], [keyComparator],
  /// [compactionStrategy], and [crashRecovery] pass through to hive_ce untouched at the
  /// eventual open. [observer] hears every event of this box, starting with that open.
  factory LazyDualKeyBox(
    String name, {
    DualKeyCodec<K1, K2>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) {
    final dualCodec = resolveDualKeyCodec<K1, K2>(codec);

    // Type arguments stay explicit through this wiring (CODESTYLE #type-safety).
    return LazyDualKeyBox<T, K1, K2>._(
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
      dualCodec: dualCodec,
      adapter: DualKeyCodecAdapter<K1, K2>(dualCodec: dualCodec),
    );
  }

  /// Wiring is internal: consumers construct via the unnamed constructor (tests use the seam
  /// below).
  LazyDualKeyBox._({required this._engine, required this._dualCodec, required this._adapter});

  /// Encodes a two-part key for the engine, which admits only encoded keys.
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K1 primary, K2 secondary) => RawKey(_adapter.encode((primary, secondary)));

  late final _scanIndex = ScanQueryIndex<K1, K2>(rawKeys: () => _engine.rawKeys, codec: _dualCodec);

  /// The box name, available before the box ever opens: the observer correlation handle.
  String get name => _engine.name;

  /// Number of stored composite keys. Sync carve-out: throws [StateError] before the first
  /// open.
  int get length => _engine.length;

  /// Whether the box holds no entries. Sync carve-out: throws [StateError] before the first
  /// open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry. Sync carve-out: throws [StateError] before the
  /// first open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys as `(primary, secondary)` records, decoded through the box's
  /// [DualKeyCodec] as they are iterated. Sync carve-out: throws [StateError] before the first
  /// open.
  Iterable<(K1, K2)> get keys => _engine.rawKeys.map(_dualCodec.decode);

  /// Every stored value when run, each read from disk and materialised into one list.
  /// Dispatches one read-all event per run.
  Task<List<T>> get values => _engine.values();

  /// Warms the box up compositionally when run; any effect performs the same open implicitly.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether ([primary], [secondary]) is stored right now. Sync carve-out: throws [StateError]
  /// before the first open.
  bool contains(K1 primary, K2 secondary) => _engine.contains(_rawKeyFor(primary, secondary));

  /// Reads the value under ([primary], [secondary]) from disk when run: `Some` when present,
  /// `None` when absent.
  TaskOption<T> get(K1 primary, K2 secondary) =>
      _engine.get(_rawKeyFor(primary, secondary), (primary, secondary));

  /// Reads the value under ([primary], [secondary]) from disk when run, falling back to
  /// [fallback] when absent.
  Task<T> getOr(K1 primary, K2 secondary, T fallback) =>
      _engine.getOr(_rawKeyFor(primary, secondary), (primary, secondary), fallback);

  /// Every value whose key's primary part equals [primary], as a plain (possibly empty) list
  /// when run: an O(K) scan over the live key set, matches fetched from disk in parallel, one
  /// read event per match. Auto-opens like any effect.
  Task<List<T>> queryByPrimary(K1 primary) => _queryFor(() => _scanIndex.rawKeysByPrimary(primary));

  /// Every value whose key's secondary part equals [secondary], as a plain (possibly empty)
  /// list when run: an O(K) scan over the live key set, matches fetched from disk in parallel,
  /// one read event per match. Auto-opens like any effect.
  Task<List<T>> queryBySecondary(K2 secondary) =>
      _queryFor(() => _scanIndex.rawKeysBySecondary(secondary));

  /// Writes [value] under ([primary], [secondary]) when run; the key gate applies as in
  /// [LazyKeyedBox.put].
  Task<Unit> put(K1 primary, K2 secondary, T value) => _engine
      .put(_rawKeyFor(primary, secondary), (primary, secondary), value)
      .map((_) => _afterWrite(primary, secondary));

  /// Writes every entry of [entries] (keyed by `(primary, secondary)` records) in one batch
  /// when run. All keys are encoded and gated at call time, so a bad key means nothing gets
  /// written.
  Task<Unit> putAll(Map<(K1, K2), T> entries) => _engine
      .putAll(
        // Lazy: the engine's own pass consumes this, so the batch is materialised once.
        entries.entries.map(
          (entry) => MapEntry(_rawKeyFor(entry.key.$1, entry.key.$2), entry.value),
        ),
      )
      .map((_) {
        for (final (primary, secondary) in entries.keys) {
          _afterWrite(primary, secondary);
        }

        return unit;
      });

  /// Rewrites the value under ([primary], [secondary]) through [update] when run and returns
  /// the new value, mirroring [Map.update]: absent is seeded by [ifAbsent], and with no
  /// [ifAbsent] the task fails with an [ArgumentError] at run time.
  Task<T> update(K1 primary, K2 secondary, T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine
          .update(_rawKeyFor(primary, secondary), (primary, secondary), update, ifAbsent: ifAbsent)
          .map((updatedValue) {
            _afterWrite(primary, secondary);

            return updatedValue;
          });

  /// Deletes ([primary], [secondary]) when run; deleting an absent key is hive's documented
  /// no-op.
  Task<Unit> delete(K1 primary, K2 secondary) => _engine
      .delete(_rawKeyFor(primary, secondary), (primary, secondary))
      .map((_) => _afterDelete(primary, secondary));

  /// Deletes every `(primary, secondary)` record in [keys] in one batch when run; observers
  /// hear one event per key.
  Task<Unit> deleteAll(Iterable<(K1, K2)> keys) {
    // Materialised: iterated once for the batch, once for the hooks.
    final keyList = keys.toList(growable: false);

    return _engine
        .deleteAll([
          for (final (primary, secondary) in keyList) _rawKeyFor(primary, secondary),
        ], keyList)
        .map((_) {
          for (final (primary, secondary) in keyList) {
            _afterDelete(primary, secondary);
          }

          return unit;
        });
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream; pass [key] as a `(primary, secondary)` record to watch one composite
  /// key only (the surface's one blessed nullable). Subscribing auto-opens like any effect.
  /// Writes carry `Some`, deletes carry `None` (the lazy engine holds no values).
  Stream<LazyTypedBoxEvent<T, (K1, K2)>> watch({(K1, K2)? key}) => _engine
      .watchRaw(key: key == null ? null : _rawKeyFor(key.$1, key.$2))
      .map(
        (event) => LazyTypedBoxEvent<T, (K1, K2)>(
          key: _dualCodec.decode(event.key as Object),
          value: Option.fromNullable(event.value as Object?).map(_engine.decodeStored),
        ),
      );

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

  Task<List<T>> _queryFor(Iterable<Object> Function() matchingRawKeys) => Task(() async {
    // The scan needs the keystore, so warm the box up first (the same open any effect does).
    await _engine.ensureInitialised().run();

    // Materialised before the awaits: the strategy scans the live key view, which would mutate
    // under concurrent writes mid-fetch.
    final rawKeys = matchingRawKeys().toList(growable: false);
    final maybeValues = await rawKeys
        .map((rawKey) => _engine.get(RawKey(rawKey), _dualCodec.decode(rawKey)).run())
        .wait;

    // Keys that vanish mid-scan read as None and drop out (races are the consumer's timeline).
    return maybeValues
        .map((maybeValue) => maybeValue.toNullable())
        .nonNulls
        .toList(growable: false);
  });

  Unit _afterWrite(K1 primary, K2 secondary) {
    _scanIndex.afterWrite(_dualCodec.encode(primary, secondary), primary, secondary);

    return unit;
  }

  Unit _afterDelete(K1 primary, K2 secondary) {
    _scanIndex.afterDelete(_dualCodec.encode(primary, secondary), primary, secondary);

    return unit;
  }
}

/// Testing seam: wires a [LazyDualKeyBox] around [openBox] instead of the real provider, so
/// unit suites drive the façade against in-memory doubles and scripted opens.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show`
/// keeps it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
LazyDualKeyBox<T, K1, K2>
lazyDualKeyBoxAround<T extends Object, K1 extends Object, K2 extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  DualKeyCodec<K1, K2>? codec,
  BoxObserver? observer,
}) {
  final dualCodec = resolveDualKeyCodec<K1, K2>(codec);

  // Explicit type arguments on purpose; see CODESTYLE #type-safety.
  return LazyDualKeyBox<T, K1, K2>._(
    engine: LazyCrudEngine<T>(
      boxName: name,
      openBox: openBox,
      valueCodec: IdentityValueCodec<T>(),
      observer: observer,
    ),
    dualCodec: dualCodec,
    adapter: DualKeyCodecAdapter<K1, K2>(dualCodec: dualCodec),
  );
}
