/// @docImport '/src/box/keyed/keyed_box.dart';
/// @docImport '/src/codec/dual/packed_int_dual_codec.dart';
/// @docImport '/src/codec/dual/string_composite_dual_codec.dart';
/// @docImport 'lazy_dual_key_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/dual/dual_key_codec.dart';
import '/src/codec/dual/dual_key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/eager_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/event/typed_box_event.dart';
import '/src/observer/box_observer.dart';
import '/src/query/scan_query_index.dart';

/// A typed, fpdart-first façade over an **eager** hive box addressed by a two-part composite key, with
/// reverse queries by either part folded in.
///
/// For the two-dimensional cases: user and day, row and column, entity and revision. Most calls take
/// the parts separately, and `(K1, K2)` records show up where a whole key has to travel ([keys], [putAll],
/// watch events). Both parts round-trip through one [DualKeyCodec], and `(int, int)` gets [StringCompositeDualCodec]
/// unless you say otherwise. Bring your own codec for other part types, and keep it bijective or the
/// reverse queries will lie to you.
///
/// [queryByPrimary] and [queryBySecondary] answer "everything at this part" with a plain list, empty
/// when nothing matches, never an `Option`. It really is an O(K) scan, though exact lookups stay O(1)
/// and the scan costs nothing until you call one. Observers hear one read per match.
///
/// Everything else works like [KeyedBox]. The key check only ever fires for a codec you wrote, since
/// the shipped ones can't produce an unstorable key.
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class DualKeyBox<T extends Object, K1 extends Object, K2 extends Object>._({
  required final EagerCrudEngine<T> _engine,
  required final DualKeyCodec<K1, K2> _dualCodec,
}) {
  /// Encodes a two-part key for the engine, which admits only encoded keys.
  ///
  /// 2 scalar arguments, never a `(K1, K2)` record. A record parameter typed from the class's own
  /// type parameters costs about 350 ns a call, which was this family's entire overhead. See [RawKey].
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K1 primary, K2 secondary) => RawKey(_dualCodec.encode(primary, secondary));

  late final _scanIndex = ScanQueryIndex<K1, K2>(rawKeys: () => _engine.rawKeys, codec: _dualCodec);

  /// The box name. Observers hear it with every event.
  String get name => _engine.name;

  /// How many composite keys are stored. Keys live in memory, so this is free.
  int get length => _engine.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys as `(primary, secondary)` records, decoded through the box's [DualKeyCodec] as
  /// they are iterated.
  Iterable<(K1, K2)> get keys => _engine.rawKeys.map(_dualCodec.decode);

  /// The stored values, served from the in-memory cache, decoded as they are iterated. Dispatches one
  /// read-all event at call time.
  Iterable<T> get values => _engine.values(_dualCodec.decode);

  /// Reads the value under ([primary], [secondary]) synchronously from memory: `Some` when present,
  /// `None` when absent.
  Option<T> get(K1 primary, K2 secondary) =>
      _engine.get(_rawKeyFor(primary, secondary), (primary, secondary));

  /// Reads the value under ([primary], [secondary]), falling back to [fallback] when absent.
  T getOr(K1 primary, K2 secondary, T fallback) =>
      _engine.getOr(_rawKeyFor(primary, secondary), (primary, secondary), fallback);

  /// Whether ([primary], [secondary]) is stored right now.
  bool contains(K1 primary, K2 secondary) => _engine.contains(_rawKeyFor(primary, secondary));

  /// Every value whose primary part is [primary], as a plain list. An O(K) scan, one read event per
  /// match.
  List<T> queryByPrimary(K1 primary) => _matchesFor(_scanIndex.rawKeysByPrimary(primary));

  /// Every value whose secondary part is [secondary], as a plain list. An O(K) scan, one read event
  /// per match.
  List<T> queryBySecondary(K2 secondary) => _matchesFor(_scanIndex.rawKeysBySecondary(secondary));

  /// Writes [value] under ([primary], [secondary]) when run. Same key check as [KeyedBox.put].
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

  /// Deletes ([primary], [secondary]) when run. Deleting an absent key is hive's documented no-op.
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
  /// Events carry record keys, and a value even on deletes.
  Stream<TypedBoxEvent<T, (K1, K2)>> watch({(K1, K2)? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key.$1, key.$2)).map((event) {
        final semanticKey = _dualCodec.decode(event.key as Object);

        return TypedBoxEvent<T, (K1, K2)>(
          key: semanticKey,
          value: _engine.decodeStored(event.value as Object, semanticKey),
          deleted: event.deleted,
        );
      });

  /// Flushes pending writes to disk when run. Maintenance, so observers only hear about failures.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run. Maintenance, so observers only hear about failures.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. Terminal, see the class doc.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. Terminal, like [close].
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();

  /// Reads every match in [rawKeys], skipping keys that vanish mid-scan (races are the consumer's timeline,
  /// not an error).
  List<T> _matchesFor(Iterable<Object> rawKeys) => rawKeys
      // Already raw, so the scan hands it straight over. The decode is only for the read event.
      .map((rawKey) => _engine.get(RawKey(rawKey), _dualCodec.decode(rawKey)).toNullable())
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

  /// Opens the box named [name] and wires a [DualKeyBox] around it, as a lazy [Task]: nothing touches
  /// disk until `.run()`.
  ///
  /// Engine setup is still hive_ce's job, so `Hive.init(path)` and your adapters come first. [codec]
  /// defaults to [StringCompositeDualCodec] for `(int, int)` parts, and any other pair without one trips
  /// an assert while wiring. [cipher], [keyComparator], [compactionStrategy] and [crashRecovery] go
  /// straight through. [observer] hears everything this box does, starting with the open.
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

        // Explicit type arguments on purpose, see CODESTYLE #type-safety.
        return DualKeyBox<T, K1, K2>._(
          engine: EagerCrudEngine<T>(
            box: box,
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

/// Testing seam: wraps a [DualKeyBox] around an already-open (or fake) [box], skipping the real provider
/// so unit suites can use in-memory doubles.
///
/// Not exported, so only suites importing this file directly can see it.
@visibleForTesting
DualKeyBox<T, K1, K2> dualKeyBoxAround<T extends Object, K1 extends Object, K2 extends Object>(
  Box<Object?> box, {
  DualKeyCodec<K1, K2>? codec,
  BoxObserver? observer,
}) {
  final dualCodec = resolveDualKeyCodec<K1, K2>(codec);

  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  return DualKeyBox<T, K1, K2>._(
    engine: EagerCrudEngine<T>(box: box, valueCodec: IdentityValueCodec<T>(), observer: observer),
    dualCodec: dualCodec,
  );
}
