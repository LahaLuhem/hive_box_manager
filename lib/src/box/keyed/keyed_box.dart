/// @docImport 'lazy_keyed_box.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

import '/src/codec/key/key_codec.dart';
import '/src/codec/key/key_codec_resolution.dart';
import '/src/core/box_provider.dart';
import '/src/core/engine/eager_crud_engine.dart';
import '/src/core/raw_key.dart';
import '/src/core/value_codec/identity_value_codec.dart';
import '/src/event/typed_box_event.dart';
import '/src/observer/box_observer.dart';

/// A typed, fpdart-first façade over an **eager** hive box of [T] values keyed by [K].
///
/// Eager means the whole box sits in memory once it is open, so reads are synchronous and never touch
/// disk. Writes and lifecycle calls hand back a [Task] instead, so nothing happens until you run it.
/// Reach for [LazyKeyedBox] when the values are big or you only ever read a few of them.
///
/// [open] is the only way in, so holding one of these means the box is open and sync reads are safe.
/// [close] and [deleteFromDisk] end that: the handle is spent, and getting back in means a fresh [open].
///
/// A key hive cannot store safely throws an [ArgumentError] at the call site, before you get a [Task]
/// back. Whatever hive itself objects to (a closed box, a missing adapter) comes out of the [Task] when
/// it runs.
///
/// `interface class`: implement it for test fakes, extending is ours.
interface class KeyedBox<T extends Object, K extends Object>._({
  required final EagerCrudEngine<T> _engine,
  required final KeyCodec<K> _codec,
}) {
  // Inlined: sits on the read path, in front of an engine get that is itself inlined.
  @pragma('vm:prefer-inline')
  RawKey _rawKeyFor(K key) => RawKey(_codec.encode(key));

  /// The box name. Observers hear it with every event.
  String get name => _engine.name;

  /// How many entries are stored. Keys live in memory, so this is free.
  int get length => _engine.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _engine.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _engine.isNotEmpty;

  /// The stored keys, decoded through the box's [KeyCodec] as they are iterated.
  Iterable<K> get keys => _engine.rawKeys.map(_codec.decode);

  /// The stored values, decoded as they are iterated. Fires one read-all event at call time.
  Iterable<T> get values => _engine.values(_codec.decode);

  /// Reads [key] from memory: `Some` when present, `None` when absent.
  // Inlined into callers, see the engine's get for why.
  @pragma('vm:prefer-inline')
  Option<T> get(K key) => _engine.get(_rawKeyFor(key), key);

  /// Reads [key], falling back to [fallback] when absent.
  T getOr(K key, T fallback) => _engine.getOr(_rawKeyFor(key), key, fallback);

  /// Whether [key] is stored right now.
  bool contains(K key) => _engine.contains(_rawKeyFor(key));

  /// Writes [value] under [key] when run. Rejects an unstorable key on the spot, see the class doc.
  Task<Unit> put(K key, T value) => _engine.put(_rawKeyFor(key), key, value);

  /// Writes every entry of [entries] in one batch when run. Keys are checked up front, so one bad key
  /// means nothing is written at all.
  Task<Unit> putAll(Map<K, T> entries) => _engine.putAll(
    // Lazy on purpose: the engine's own pass consumes it, so the batch gets built once, not twice.
    entries.entries.map((entry) => MapEntry(_rawKeyFor(entry.key), entry.value)),
  );

  /// Writes every value in [values] when run, each under the key [key] pulls out of it.
  ///
  /// Handy when values carry their own id. Use [putAll] when they don't, which is most of the time.
  /// 2 values landing on the same key trips an assert in development, and in release the later one
  /// wins.
  Task<Unit> putAllBy(Iterable<T> values, {required K Function(T value) key}) =>
      _engine.putAll(values.map((value) => MapEntry(_rawKeyFor(key(value)), value)));

  /// Rewrites [key] through [update] when run and returns the new value, same deal as [Map.update].
  /// An absent key is seeded by [ifAbsent], and without one the task fails with an [ArgumentError].
  Task<T> update(K key, T Function(T value) update, {T Function()? ifAbsent}) =>
      _engine.update(_rawKeyFor(key), key, update, ifAbsent: ifAbsent);

  /// Deletes [key] when run. Deleting something that isn't there is a no-op.
  Task<Unit> delete(K key) => _engine.delete(_rawKeyFor(key), key);

  /// Deletes every key in [keys] in one batch when run. Observers hear one event per key.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Built once: the batch needs raw keys, the hooks need semantic ones.
    final keyList = keys.toList(growable: false);

    return _engine.deleteAll([for (final key in keyList) _rawKeyFor(key)], keyList);
  }

  /// Removes every entry when run.
  Task<Unit> clear() => _engine.clear();

  /// Typed change stream. Pass [key] to watch one key only, the one nullable on this surface and a toggle
  /// you pass rather than a value you get back.
  ///
  /// Deletes still carry a [TypedBoxEvent.value]: eager hive_ce hands back the value it just dropped
  /// from its cache, so there is nothing to null-check.
  Stream<TypedBoxEvent<T, K>> watch({K? key}) =>
      _engine.watchRaw(key: key == null ? null : _rawKeyFor(key)).map((event) {
        final semanticKey = _codec.decode(event.key as Object);

        return TypedBoxEvent<T, K>(
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

  /// Opens the box called [name] and wraps a [KeyedBox] around it. Nothing touches disk until you run
  /// the task.
  ///
  /// Engine setup is still hive_ce's job, so `Hive.init(path)` and your adapters come first. Opening
  /// a name twice joins the same underlying box, and opening it as a different kind of box fails inside
  /// the task with hive's own error.
  ///
  /// [codec] defaults by key type: `int` and `String` get the identity codecs, and any other [K] without
  /// one trips an assert while wiring, before the task exists. [cipher], [keyComparator], [compactionStrategy]
  /// and [crashRecovery] go straight through to hive_ce. [observer] hears everything this box does,
  /// starting with the open.
  static Task<KeyedBox<T, K>> open<T extends Object, K extends Object>(
    String name, {
    KeyCodec<K>? codec,
    HiveCipher? cipher,
    BoxObserver? observer,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) {
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

        // Explicit type arguments: a bare `const IdentityValueCodec()` can't mention T, so inference
        // quietly picks `Never` and the first put blows up at run time.
        return KeyedBox<T, K>._(
          engine: EagerCrudEngine<T>(
            box: box,
            valueCodec: IdentityValueCodec<T>(),
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

/// Testing seam: wraps a [KeyedBox] around an already-open (or fake) [box], skipping the real provider
/// so unit suites can drive the façade against in-memory doubles. Not exported, so only suites that
/// import this file directly can see it.
@visibleForTesting
KeyedBox<T, K> keyedBoxAround<T extends Object, K extends Object>(
  Box<Object?> box, {
  KeyCodec<K>? codec,
  BoxObserver? observer,
}) => KeyedBox<T, K>._(
  // Explicit type arguments on purpose, see the note inside `open`.
  engine: EagerCrudEngine<T>(box: box, valueCodec: IdentityValueCodec<T>(), observer: observer),
  codec: resolveKeyCodec<K>(codec),
);
