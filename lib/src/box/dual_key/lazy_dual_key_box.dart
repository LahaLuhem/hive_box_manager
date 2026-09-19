/// @docImport '/src/box/keyed/lazy_keyed_box.dart';
/// @docImport '/src/codec/dual/packed_int_dual_codec.dart';
/// @docImport '/src/codec/dual/string_composite_dual_codec.dart';
/// @docImport 'dual_key_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/dual/dual_key_codec.dart';
import '/src/codec/dual/dual_key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/event/lazy_typed_box_event.dart';
import '/src/observer/box_observer.dart';
import '/src/query/scan_query_index.dart';

/// A typed, fpdart-first façade over a **lazy** hive box addressed by a two-part composite key, with
/// reverse queries by either part folded in.
///
/// The dual-key surface on the lazy axis, so hive holds only the keystore and fetches each value off
/// disk when asked. Reads are effects as a result, queries included. Reach for [DualKeyBox] when the
/// box is read often and fits in RAM comfortably.
///
/// [queryByPrimary] and [queryBySecondary] answer "everything at this part" with a plain list in a [Task],
/// empty when nothing matches. An O(K) scan, matches fetched off disk in parallel, one read event per
/// match.
///
/// Open-on-first-use, the sync inspectors, the key check and the terminal [close] all work like [LazyKeyedBox].
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class LazyDualKeyBox<T extends Object, K1 extends Object, K2 extends Object>._({
  required final LazyCrudEngine<T> _engine,
  required final DualKeyCodec<K1, K2> _dualCodec,
}) {
  /// Wires up a box that opens on first use. Building it touches nothing.
  ///
  /// Engine setup is still hive_ce's job, so `Hive.init(path)` and your adapters come first, before
  /// the first effect runs. [codec] defaults to [StringCompositeDualCodec] for `(int, int)` parts, and
  /// any other pair without one trips an assert while wiring. [cipher], [keyComparator], [compactionStrategy]
  /// and [crashRecovery] go straight through at the eventual open. [observer] hears everything this
  /// box does, starting with that open.
  factory(
    String name, {
    DualKeyCodec<K1, K2>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) {
    final dualCodec = resolveDualKeyCodec<K1, K2>(codec);

    // Explicit type arguments on purpose, see CODESTYLE #type-safety.
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
    );
  }

  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K1 primary, K2 secondary) => RawKey(_dualCodec.encode(primary, secondary));

  late final _scanIndex = ScanQueryIndex<K1, K2>(rawKeys: () => _engine.rawKeys, codec: _dualCodec);

  /// The box name, there before the box ever opens. Observers hear it with every event.
  String get name => _engine.name;

  /// Number of stored composite keys. Sync carve-out: throws [StateError] before the first open.
  int get length => _engine.length;

  /// Whether the box holds no entries. Throws a [StateError] before the first open.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry. Throws a [StateError] before the first open.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys as `(primary, secondary)` records, decoded through the box's [DualKeyCodec] as
  /// they are iterated. Sync carve-out: throws [StateError] before the first open.
  Iterable<(K1, K2)> get keys => _engine.rawKeys.map(_dualCodec.decode);

  /// Every stored value when run, each read from disk and materialised into one list. Dispatches one
  /// read-all event per run.
  Task<List<T>> get values => _engine.values(_dualCodec.decode);

  /// Opens the box when run. Any effect would do it anyway, this just gets it out of the way.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether ([primary], [secondary]) is stored right now. Sync carve-out: throws [StateError] before
  /// the first open.
  bool contains(K1 primary, K2 secondary) => _engine.contains(_rawKeyFor(primary, secondary));

  /// Reads the value under ([primary], [secondary]) from disk when run: `Some` when present, `None`
  /// when absent.
  TaskOption<T> get(K1 primary, K2 secondary) =>
      _engine.get(_rawKeyFor(primary, secondary), (primary, secondary));

  /// Reads the value under ([primary], [secondary]) from disk when run, falling back to [fallback] when
  /// absent.
  Task<T> getOr(K1 primary, K2 secondary, T fallback) =>
      _engine.getOr(_rawKeyFor(primary, secondary), (primary, secondary), fallback);

  /// Every value whose primary part is [primary], as a plain list when run. An O(K) scan, matches fetched
  /// off disk in parallel, one read event per match.
  Task<List<T>> queryByPrimary(K1 primary) => _queryFor(() => _scanIndex.rawKeysByPrimary(primary));

  /// Every value whose secondary part is [secondary], as a plain list when run. An O(K) scan, matches
  /// fetched off disk in parallel, one read event per match.
  Task<List<T>> queryBySecondary(K2 secondary) =>
      _queryFor(() => _scanIndex.rawKeysBySecondary(secondary));

  /// Writes [value] under ([primary], [secondary]) when run. Same key check as [LazyKeyedBox.put].
  Task<Unit> put(K1 primary, K2 secondary, T value) => _engine
      .put(_rawKeyFor(primary, secondary), (primary, secondary), value)
      .map((_) => _afterWrite(primary, secondary));

  /// Writes every entry of [entries], keyed by `(primary, secondary)` records, in one batch when run.
  /// Keys are checked up front, so one bad key means nothing is written at all.
  Task<Unit> putAll(Map<(K1, K2), T> entries) => _engine
      .putAll(
        // Lazy on purpose: the engine's own pass consumes it, so the batch gets built once, not twice.
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

  /// Writes every value in [values] when run, each under the 2 parts [primary] and [secondary] extract
  /// from it.
  ///
  /// Worth more here than on the keyed boxes: [putAll] makes you build a `(K1, K2)`-keyed map, and hashing
  /// a record per entry is the expensive bit. This way no record is built at all.
  ///
  /// Use [putAll] when the parts don't come from the value, say a grid or a legacy key set.
  ///
  /// 2 values landing on the same pair trips an assert in development, and in release the later one
  /// wins.
  Task<Unit> putAllBy(
    Iterable<T> values, {
    required K1 Function(T value) primary,
    required K2 Function(T value) secondary,
  }) {
    // Built up front: the engine consumes the entries, then the query hooks replay them. That runs the
    // extractors twice per value, so keep them cheap.
    final valueList = values.toList(growable: false);

    return _engine
        .putAll(
          valueList.map((value) => MapEntry(_rawKeyFor(primary(value), secondary(value)), value)),
        )
        .map((_) {
          for (final value in valueList) {
            _afterWrite(primary(value), secondary(value));
          }

          return unit;
        });
  }

  /// Rewrites the value under ([primary], [secondary]) through [update] when run and returns the new
  /// value, mirroring [Map.update]: absent is seeded by [ifAbsent], and with no [ifAbsent] the task
  /// fails with an [ArgumentError] at run time.
  Task<T> update(K1 primary, K2 secondary, T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine
          .update(_rawKeyFor(primary, secondary), (primary, secondary), update, ifAbsent: ifAbsent)
          .map((updatedValue) {
            _afterWrite(primary, secondary);

            return updatedValue;
          });

  /// Deletes ([primary], [secondary]) when run. Deleting something that isn't there is a no-op.
  Task<Unit> delete(K1 primary, K2 secondary) => _engine
      .delete(_rawKeyFor(primary, secondary), (primary, secondary))
      .map((_) => _afterDelete(primary, secondary));

  /// Deletes every `(primary, secondary)` record in [keys] in one batch when run. Observers hear one
  /// event per key.
  Task<Unit> deleteAll(Iterable<(K1, K2)> keys) {
    // Built once: iterated for the batch, then again for the hooks.
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

  /// Typed change stream. Pass [key] as a `(primary, secondary)` record to watch one composite key.
  /// Writes carry `Some` and deletes carry `None`, since a lazy box holds no values.
  Stream<LazyTypedBoxEvent<T, (K1, K2)>> watch({(K1, K2)? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key.$1, key.$2)).map((event) {
        final semanticKey = _dualCodec.decode(event.key as Object);

        return LazyTypedBoxEvent<T, (K1, K2)>(
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

  Task<List<T>> _queryFor(Iterable<Object> Function() matchingRawKeys) => Task(() async {
    // The scan needs the keystore, so warm the box up first (the same open any effect does).
    await _engine.ensureInitialised().run();

    // Materialised before the awaits: the strategy scans the live key view, which would mutate under
    // concurrent writes mid-fetch.
    final rawKeys = matchingRawKeys().map(RawKey.new).toList(growable: false);
    // Delegated so one bad record names its own key.
    final maybeValues = await _engine.getEach(rawKeys, _dualCodec.decode).run();

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

/// Testing seam: wraps a [LazyDualKeyBox] around [openBox] rather than the real provider, so unit suites
/// can use in-memory doubles and scripted opens.
///
/// Not exported, so only suites importing this file directly can see it.
@visibleForTesting
LazyDualKeyBox<T, K1, K2>
lazyDualKeyBoxAround<T extends Object, K1 extends Object, K2 extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  DualKeyCodec<K1, K2>? codec,
  BoxObserver? observer,
}) {
  final dualCodec = resolveDualKeyCodec<K1, K2>(codec);

  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  return LazyDualKeyBox<T, K1, K2>._(
    engine: LazyCrudEngine<T>(
      boxName: name,
      openBox: openBox,
      valueCodec: IdentityValueCodec<T>(),
      observer: observer,
    ),
    dualCodec: dualCodec,
  );
}
