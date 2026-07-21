/// @docImport '../codec/dual/packed_int_dual_codec.dart';
/// @docImport '../codec/dual/string_composite_dual_codec.dart';
/// @docImport 'keyed_box.dart';
/// @docImport 'lazy_dual_key_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '../codec/dual/dual_key_codec.dart';
import '../codec/dual/dual_key_codec_adapter.dart';
import '../codec/dual/dual_key_codec_resolution.dart';
import '../core/box_provider.dart';
import '../core/engine/eager_crud_engine.dart';
import '../core/value_codec/identity_value_codec.dart';
import '../event/typed_box_event.dart';
import '../observer/box_observer.dart';
import '../query/scan_query_index.dart';

/// A typed, fpdart-first façade over an **eager** hive box addressed by a two-part composite
/// key, with reverse queries by either part folded in.
///
/// The two-dimensional scenario: user + day, row + column, entity + revision. Every operation
/// takes the parts separately ([get], [put], [contains], ...) or as `(K1, K2)` records where a
/// whole key travels ([keys], [putAll], watch events). Both parts round-trip through one
/// [DualKeyCodec]: `(int, int)` parts default to the safe [StringCompositeDualCodec] (full-range
/// parts, negatives included), and [PackedIntDualCodec] is the measured performance opt-in with
/// its 16-bit-per-part ceiling. Any other part types take a consumer codec; keep it bijective or
/// reverse queries will lie.
///
/// [queryByPrimary] / [queryBySecondary] answer "everything at this part" with a plain,
/// possibly-empty list, never an `Option` (no matches is a real, empty answer). 1.0's strategy
/// is an honest **O(K) scan** over the live key set: exact lookups stay O(1), and the scan
/// costs nothing until called. Queries read each match, so observers hear one read per matched
/// key.
///
/// Everything else matches [KeyedBox]: eager reads are synchronous and disk-free, effects are
/// lazy [Task]s, the write path gates raw keys with a synchronous [ArgumentError] (the shipped
/// codecs cannot produce an unstorable key; the gate guards consumer codecs), engine failures
/// surface unwrapped inside tasks, and [close] / [deleteFromDisk] are terminal.
///
/// `interface class`: implement it for test fakes; extending is reserved to this package.
interface class DualKeyBox<T extends Object, K1 extends Object, K2 extends Object> {
  final EagerCrudEngine<T, (K1, K2)> _engine;
  final DualKeyCodec<K1, K2> _dualCodec;
  late final _scanIndex = ScanQueryIndex<K1, K2>(rawKeys: () => _engine.rawKeys, codec: _dualCodec);

  /// Wiring is internal: acquisition goes through [open] (tests use the seam below).
  DualKeyBox._({required this._engine, required this._dualCodec});

  /// The box name: the correlation handle observers receive with every event.
  String get name => _engine.name;

  /// Number of stored composite keys; keys always live in memory, so this is free.
  int get length => _engine.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys as `(primary, secondary)` records, decoded through the box's
  /// [DualKeyCodec] as they are iterated.
  Iterable<(K1, K2)> get keys => _engine.keys;

  /// The stored values, served from the in-memory cache, decoded as they are iterated.
  /// Dispatches one read-all event at call time.
  Iterable<T> get values => _engine.values;

  /// Reads the value under ([primary], [secondary]) synchronously from memory: `Some` when
  /// present, `None` when absent.
  Option<T> get(K1 primary, K2 secondary) => _engine.get((primary, secondary));

  /// Reads the value under ([primary], [secondary]), falling back to [fallback] when absent.
  T getOr(K1 primary, K2 secondary, T fallback) => _engine.getOr((primary, secondary), fallback);

  /// Whether ([primary], [secondary]) is stored right now.
  bool contains(K1 primary, K2 secondary) => _engine.contains((primary, secondary));

  /// Every value whose key's primary part equals [primary], as a plain (possibly empty) list:
  /// an O(K) scan over the live key set, one read event per match.
  List<T> queryByPrimary(K1 primary) => _matchesFor(_scanIndex.rawKeysByPrimary(primary));

  /// Every value whose key's secondary part equals [secondary], as a plain (possibly empty)
  /// list: an O(K) scan over the live key set, one read event per match.
  List<T> queryBySecondary(K2 secondary) => _matchesFor(_scanIndex.rawKeysBySecondary(secondary));

  /// Writes [value] under ([primary], [secondary]) when run; the key gate applies as in
  /// [KeyedBox.put].
  Task<Unit> put(K1 primary, K2 secondary, T value) =>
      _engine.put((primary, secondary), value).map((_) => _afterWrite(primary, secondary));

  /// Writes every entry of [entries] (keyed by `(primary, secondary)` records) in one batch
  /// when run. All keys are encoded and gated at call time, so a bad key means nothing gets
  /// written.
  Task<Unit> putAll(Map<(K1, K2), T> entries) => _engine.putAll(entries).map((_) {
    for (final (primary, secondary) in entries.keys) {
      _afterWrite(primary, secondary);
    }

    return unit;
  });

  /// Rewrites the value under ([primary], [secondary]) through [update] when run and returns
  /// the new value, mirroring [Map.update]: absent is seeded by [ifAbsent], and with no
  /// [ifAbsent] the task fails with an [ArgumentError] at run time.
  Task<T> update(K1 primary, K2 secondary, T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update((primary, secondary), update, ifAbsent: ifAbsent).map((updatedValue) {
        _afterWrite(primary, secondary);

        return updatedValue;
      });

  /// Deletes ([primary], [secondary]) when run; deleting an absent key is hive's documented
  /// no-op.
  Task<Unit> delete(K1 primary, K2 secondary) =>
      _engine.delete((primary, secondary)).map((_) => _afterDelete(primary, secondary));

  /// Deletes every `(primary, secondary)` record in [keys] in one batch when run; observers
  /// hear one event per key.
  Task<Unit> deleteAll(Iterable<(K1, K2)> keys) {
    // Materialised: iterated once for the batch, once for the hooks.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll(keyList).map((_) {
      for (final (primary, secondary) in keyList) {
        _afterDelete(primary, secondary);
      }

      return unit;
    });
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream; pass [key] as a `(primary, secondary)` record to watch one composite
  /// key only (the surface's one blessed nullable). Events carry record keys and non-null
  /// values, even on deletes (the eager promise).
  Stream<TypedBoxEvent<T, (K1, K2)>> watch({(K1, K2)? key}) => _engine.watch(key: key);

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

  /// Reads every match in [rawKeys], skipping keys that vanish mid-scan (races are the
  /// consumer's timeline, not an error).
  List<T> _matchesFor(Iterable<Object> rawKeys) => rawKeys
      .map((rawKey) => _engine.get(_dualCodec.decode(rawKey)).toNullable())
      .nonNulls
      .toList(growable: false);

  Unit _afterWrite(K1 primary, K2 secondary) {
    _scanIndex.afterWrite(_dualCodec.encode(primary, secondary), primary, secondary);

    return unit;
  }

  Unit _afterDelete(K1 primary, K2 secondary) {
    _scanIndex.afterDelete(_dualCodec.encode(primary, secondary), primary, secondary);

    return unit;
  }

  /// Opens the box named [name] and wires a [DualKeyBox] around it, as a lazy [Task]: nothing
  /// touches disk until `.run()`.
  ///
  /// One-time engine setup stays hive_ce's, exactly as it documents: `Hive.init(path)` (or
  /// `Hive.initFlutter()`) plus adapter registration. [codec] defaults by part types:
  /// `(int, int)` resolves to [StringCompositeDualCodec], and any other pair without an
  /// explicit codec fails an assert synchronously at wiring time. [cipher], [keyComparator],
  /// [compactionStrategy], and [crashRecovery] pass through to hive_ce untouched. [observer]
  /// hears every event of this box, starting with the open itself.
  static Task<DualKeyBox<T, K1, K2>> open<T extends Object, K1 extends Object, K2 extends Object>(
    String name, {
    DualKeyCodec<K1, K2>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) {
    final dualCodec = resolveDualKeyCodec<K1, K2>(codec);

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

        // Type arguments stay explicit through this wiring (CODESTYLE #type-safety).
        return DualKeyBox<T, K1, K2>._(
          engine: EagerCrudEngine<T, (K1, K2)>(
            box: box,
            keyCodec: DualKeyCodecAdapter<K1, K2>(dualCodec: dualCodec),
            valueCodec: IdentityValueCodec<T>(),
            observer: observer,
          ),
          dualCodec: dualCodec,
        );
      } on Object catch (error, stackTrace) {
        observer?.onOperationError(name, 'open', error, stackTrace);
        rethrow;
      }
    });
  }
}

/// Testing seam: wires a [DualKeyBox] around an already-open (or fake) [box] instead of going
/// through the real provider, so unit suites drive the façade against in-memory doubles.
///
/// Same library as the façade on purpose, and deliberately not exported: the barrel's `show`
/// keeps it out of the public API, so it exists only for suites importing this file directly.
@visibleForTesting
DualKeyBox<T, K1, K2> dualKeyBoxAround<T extends Object, K1 extends Object, K2 extends Object>(
  Box<Object?> box, {
  DualKeyCodec<K1, K2>? codec,
  BoxObserver? observer,
}) {
  final dualCodec = resolveDualKeyCodec<K1, K2>(codec);

  // Explicit type arguments on purpose; see CODESTYLE #type-safety.
  return DualKeyBox<T, K1, K2>._(
    engine: EagerCrudEngine<T, (K1, K2)>(
      box: box,
      keyCodec: DualKeyCodecAdapter<K1, K2>(dualCodec: dualCodec),
      valueCodec: IdentityValueCodec<T>(),
      observer: observer,
    ),
    dualCodec: dualCodec,
  );
}
