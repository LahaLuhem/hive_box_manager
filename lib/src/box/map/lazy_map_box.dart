/// @docImport 'map_box.dart';
library;

import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/lazy_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/map_cast_value_codec.dart';
import '/src/event/lazy_typed_box_event.dart';
import '/src/observer/box_observer.dart';
import 'map_edits.dart';

/// A **lazy** box holding a `Map` of [MK] to [MV] per [K] key, read off disk when asked.
///
/// Same rules as [MapBox]: the inner keys are strings, numbers, bools or enums, and a write with an
/// int key hive can't store exactly fails.
///
/// It opens on the first effect. Until then the sync inspectors ([length], [isEmpty], [isNotEmpty],
/// [keys], [contains]) throw a [StateError].
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class LazyMapBox<MK extends Object, MV extends Object, K extends Object>._({
  required final LazyCrudEngine<Map<MK, MV>> _engine,
  required final KeyCodec<K> _codec,
}) {
  /// Wires up a box that opens on first use, so `Hive.init` and your adapters only need to be ready
  /// by the first effect. Leaving out [codec] where [K] needs one trips an assert, and so does an [MK]
  /// or [MV] a restart would break.
  new(
    String name, {
    KeyCodec<K>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) : this._(
         // Explicit type arguments on purpose, see CODESTYLE #type-safety.
         engine: LazyCrudEngine<Map<MK, MV>>(
           boxName: name,
           openBox: () => BoxProvider().openLazyBox(
             name,
             cipher: cipher,
             keyComparator: keyComparator,
             compactionStrategy: compactionStrategy,
             crashRecovery: crashRecovery,
           ),
           valueCodec: MapCastValueCodec<MK, MV>(),
           observer: observer,
         ),
         codec: resolveKeyCodec<K>(codec),
       );

  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name, there before the box opens.
  String get name => _engine.name;

  /// How many keys are stored, not how many entries.
  int get length => _engine.length;

  /// Whether the box holds no keys.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one key.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// Every stored map when run.
  Task<List<Map<MK, MV>>> get values => _engine.values(_codec.decode);

  /// Opens the box when run, if you'd rather not wait for the first effect.
  Task<Unit> ensureInitialised() => _engine.ensureInitialised();

  /// Whether [key] is stored.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// The map under [key] when run, or `None` when it's absent.
  TaskOption<Map<MK, MV>> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// The map under [key] when run, or an empty one. Use [get] to tell absent from stored-empty.
  Task<Map<MK, MV>> getOr(K key) =>
      _engine.get(_rawKeyFor(key), key).getOrElse(() => UnmodifiableMapView(<MK, MV>{}));

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

  /// Typed changes, for [key] alone if given. Deletes carry `None`, since a lazy box keeps no values.
  Stream<LazyTypedBoxEvent<Map<MK, MV>, K>> watch({K? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key)).map((event) {
        final semanticKey = _codec.decode(event.key as Object);

        return LazyTypedBoxEvent<Map<MK, MV>, K>(
          key: semanticKey,
          value: Option.fromNullable(event.value as Object?)
              .map((storedValue) => _engine.decodeStored(storedValue, semanticKey)),
        );
      });

  /// Flushes pending writes to disk when run.
  Task<Unit> flush() => _engine.flush();

  /// Compacts the box file when run.
  Task<Unit> compact() => _engine.compact();

  /// Closes the box when run. This handle is done after that, even if it never opened.
  Task<Unit> close() => _engine.close();

  /// Deletes the box from disk when run, opening it first if needed. This handle is done after that.
  Task<Unit> deleteFromDisk() => _engine.deleteFromDisk();
}

/// Testing seam: a [LazyMapBox] around [openBox] instead of the real provider. Not exported.
@visibleForTesting
LazyMapBox<MK, MV, K> lazyMapBoxAround<MK extends Object, MV extends Object, K extends Object>(
  String name,
  Future<LazyBox<Object?>> Function() openBox, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => LazyMapBox<MK, MV, K>._(
  // Explicit type arguments on purpose, see CODESTYLE #type-safety.
  engine: LazyCrudEngine<Map<MK, MV>>(
    boxName: name,
    openBox: openBox,
    valueCodec: MapCastValueCodec<MK, MV>(),
    observer: observer,
  ),
  codec: resolveKeyCodec<K>(codec),
);
