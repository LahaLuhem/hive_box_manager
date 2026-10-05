/// @docImport '../list/list_box.dart';
library;

import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/eager_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/map_cast_value_codec.dart';
import '/src/event/typed_box_event.dart';
import '/src/observer/box_observer.dart';
import 'map_edits.dart';

/// An **eager** box holding a `Map` of [MK] to [MV] per [K] key.
///
/// The inner keys have to be a `String`, `num`, `bool` or enum, the types sure to still match after
/// a restart hands back fresh objects. Key by an id otherwise. A write with an int key hive can't store
/// exactly (some past 2^53) fails at the call, or for [update] when it runs.
///
/// Writes are copied and reads can't be changed. Everything else works like [ListBox].
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class MapBox<MK extends Object, MV extends Object, K extends Object>._({
  required final EagerCrudEngine<Map<MK, MV>> _engine,
  required final KeyCodec<K> _codec,
}) {
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name. Observers hear it with every event.
  String get name => _engine.name;

  /// How many keys are stored, not how many entries.
  int get length => _engine.length;

  /// Whether the box holds no keys.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one key.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// The stored maps.
  Iterable<Map<MK, MV>> get values => _engine.values(_codec.decode);

  /// The map under [key], or `None` when it's absent.
  Option<Map<MK, MV>> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// The map under [key], or an empty one. Use [get] to tell absent from stored-empty.
  Map<MK, MV> getOr(K key) => get(key).getOrElse(() => UnmodifiableMapView(<MK, MV>{}));

  /// Whether [key] is stored.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Stores [entries] under [key] when run.
  Task<Unit> put(K key, Map<MK, MV> entries) =>
      _engine.put(_rawKeyFor(key), key, storableCopyOf(entries));

  /// [put] for every entry of [entries], in one batch.
  Task<Unit> putAll(Map<K, Map<MK, MV>> entries) => _engine.putAll(
    // Left lazy so the engine builds the batch in one pass.
    entries.entries.map((entry) => MapEntry(_rawKeyFor(entry.key), storableCopyOf(entry.value))),
  );

  /// Rewrites the map under [key] through [update] when run, like [Map.update].
  Task<Map<MK, MV>> update(
    K key,
    Map<MK, MV> Function(Map<MK, MV> entries) update, {
    Map<MK, MV> Function()? ifAbsent,
  }) => _engine
      .update(
        _rawKeyFor(key),
        key,
        (entries) => storableCopyOf(update(entries)),
        ifAbsent: ifAbsent == null ? null : () => storableCopyOf(ifAbsent()),
      )
      .map(UnmodifiableMapView.new);

  /// Adds [entries] to the map under [key] when run, like [Map.addAll], so a stored entry takes the
  /// incoming value. A key that isn't there yet gets a copy of [entries].
  Task<Unit> addAll(K key, Map<MK, MV> entries) {
    // Copied now, so a bad int key fails at the call like put's.
    final incomingEntries = storableCopyOf(entries);

    return _engine
        .update(
          _rawKeyFor(key),
          key,
          // Fresh maps by construction, so neither path needs another copy.
          (storedEntries) => {...storedEntries, ...incomingEntries},
          ifAbsent: () => incomingEntries,
        )
        .map((_) => unit);
  }

  /// Takes the entry under [entryKey] out of the map under [key] when run, like [Map.remove]. The key
  /// stays, even once its map is empty.
  Task<Unit> remove(K key, MK entryKey) => _engine.edit(
    _rawKeyFor(key),
    key,
    (storedOrNone) => storedOrNone
        .filter((storedEntries) => storedEntries.containsKey(entryKey))
        .map((storedEntries) => Map<MK, MV>.of(storedEntries)..remove(entryKey)),
  );

  /// Deletes [key] and its map when run.
  Task<Unit> delete(K key) => _engine.delete(_rawKeyFor(key), key);

  /// Deletes every key in [keys] in one batch when run.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Copied so a lazy [keys] isn't walked twice.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll(keyList.map(_rawKeyFor).toList(growable: false), keyList);
  }

  /// Deletes every key when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed changes, for [key] alone if given. Deletes still carry the old map.
  Stream<TypedBoxEvent<Map<MK, MV>, K>> watch({K? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key)).map((event) {
        final semanticKey = _codec.decode(event.key as Object);

        return TypedBoxEvent<Map<MK, MV>, K>(
          key: semanticKey,
          value: _engine.decodeStored(event.value as Object, semanticKey),
          deleted: event.deleted,
        );
      });

  /// Flushes pending writes to disk when run.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. This handle is done after that.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run. This handle is done after that.
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();

  /// Opens the box named [name] when run. Any adapter you register is for [MK] or [MV], the map itself
  /// needs none.
  ///
  /// Leaving out [codec] where [K] needs one trips an assert, as does an [MK] or [MV] a restart would
  /// break. The hive options go straight through, and [observer] hears everything from the open on.
  static Task<MapBox<MK, MV, K>> open<MK extends Object, MV extends Object, K extends Object>(
    String name, {
    KeyCodec<K>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) {
    // Built before the Task, so its wiring asserts fire at the call like the key codec's.
    final valueCodec = MapCastValueCodec<MK, MV>();
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

        // Explicit type arguments on purpose, see CODESTYLE #type-safety.
        return MapBox<MK, MV, K>._(
          engine: EagerCrudEngine<Map<MK, MV>>(
            box: box,
            valueCodec: valueCodec,
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

/// Testing seam: a [MapBox] around an open or fake [box]. Not exported.
@visibleForTesting
MapBox<MK, MV, K> mapBoxAround<MK extends Object, MV extends Object, K extends Object>(
  Box<Object?> box, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => MapBox<MK, MV, K>._(
  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  engine: EagerCrudEngine<Map<MK, MV>>(
    box: box,
    valueCodec: MapCastValueCodec<MK, MV>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
);
