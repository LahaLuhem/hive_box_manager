import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';

import '/src/observer/box_observer.dart';
import '../raw_key.dart';
import '../raw_key_gate.dart';
import '../value_codec/value_codec.dart';

/// The eager CRUD engine: every eager façade delegates here, so CRUD is written exactly once.
///
/// Owns hive and the corruption gate; façades own their codecs. Keys arrive encoded as [RawKey],
/// with the semantic key alongside purely so observers hear what a consumer would recognise.
/// Keeping codecs out is what removes the `KeyCodec<(K1, K2)>` adapter the dual façades would otherwise
/// need, and its ~350 ns per op (`benchmark/key_shape_bench.dart`).
///
/// Sync reads are legal by construction: an eager engine only exists around an already-open box.
/// `close()` / `deleteFromDisk()` are terminal, after which operations surface the engine's own
/// already-closed error (tier 3: no wrapper pre-check). A codec emitting a non-storable raw key
/// throws at the call site, before any [Task] is built.
final class EagerCrudEngine<T extends Object> {
  final Box<Object?> _box;
  final ValueCodec<T> _valueCodec;
  final BoxObserver? _observer;

  /// Wires the engine around an open [_box].
  new({required this._box, required this._valueCodec, this._observer});

  /// The underlying box name: the observer correlation handle.
  String get name => _box.name;

  /// Number of stored entries (keys live in memory on both axes).
  int get length => _box.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _box.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _box.isNotEmpty;

  /// The stored keys exactly as hive holds them. Façades decode; the query strategies scan.
  Iterable<Object> get rawKeys => _box.keys.map((rawKey) => rawKey as Object);

  /// The stored values, decoded lazily; dispatches one read-all event at call time.
  Iterable<T> get values {
    _observer?.onReadAll(name, _box.length);

    return _box.values.map((storedValue) => _valueCodec.fromStored(storedValue!));
  }

  /// Restores a stored value through the value codec, for façades assembling their watch events.
  T decodeStored(Object storedValue) => _valueCodec.fromStored(storedValue);

  /// Reads [rawKey], `None` when absent. [semanticKey] is what observers hear.
  // Inlined into callers: the wrapper-overhead lane holds the eager read to raw-hive speed, and call
  // frames are the one cost the compiler can erase here (the Some allocation is contract).
  @pragma('vm:prefer-inline')
  Option<T> get(RawKey rawKey, Object semanticKey) {
    final storedValue = _box.get(rawKey.value);
    _observer?.onRead(name, semanticKey, storedValue);

    return storedValue == null ? const None() : Some(_valueCodec.fromStored(storedValue));
  }

  /// Reads [rawKey], falling back to [fallback] when absent.
  T getOr(RawKey rawKey, Object semanticKey, T fallback) =>
      get(rawKey, semanticKey).getOrElse(() => fallback);

  /// Whether [rawKey] is stored right now. No observer event, so no semantic key is needed.
  bool contains(RawKey rawKey) => _box.containsKey(rawKey.value);

  /// Writes [value] under [rawKey].
  Task<Unit> put(RawKey rawKey, Object semanticKey, T value) {
    ensureStorableRawKey(rawKey.value);

    return _guard('put', () async {
      await _box.put(rawKey.value, _valueCodec.toStorable(value));
      _observer?.onWritten(name, semanticKey, value);

      return unit;
    });
  }

  /// Writes every entry of [rawEntries] in one batch. No semantic keys: the event carries a count.
  ///
  /// Lazy iterable, consumed eagerly here: the façade's encode fuses into this pass (one materialisation, not two)
  /// while a bad key still fails before the [Task] exists.
  ///
  /// Two entries encoding to one raw key is an assert, not an error: in release the later entry wins
  /// (plain `Map` semantics), so a batch that quietly drops rows gets caught in development instead
  /// of shipping. It means either two values yielded the same key, or the codec is not injective.
  Task<Unit> putAll(Iterable<MapEntry<RawKey, T>> rawEntries) {
    final storableEntries = <Object, Object?>{};
    for (final entry in rawEntries) {
      final rawKey = entry.key.value;
      ensureStorableRawKey(rawKey);
      assert(
        !storableEntries.containsKey(rawKey),
        'putAll: two entries encode to raw key $rawKey, so the later one silently wins. Either '
        'two values yielded the same key, or the key codec is not injective.',
      );
      storableEntries[rawKey] = _valueCodec.toStorable(entry.value);
    }

    return _guard('putAll', () async {
      await _box.putAll(storableEntries);
      _observer?.onWrittenAll(name, storableEntries.length);

      return unit;
    });
  }

  /// Rewrites [rawKey] through [update], mirroring `Map.update`: absent + no [ifAbsent] is an [ArgumentError]
  /// inside the task, evaluated when it runs.
  Task<T> update(
    RawKey rawKey,
    Object semanticKey,
    T Function(T value) update, {
    T Function()? ifAbsent,
  }) {
    ensureStorableRawKey(rawKey.value);

    return _guard('update', () async {
      final storedValue = _box.get(rawKey.value);
      final updatedValue = storedValue == null
          ? (ifAbsent ??
                (() => throw ArgumentError.value(
                  semanticKey,
                  'key',
                  'absent, and no ifAbsent was given (mirrors Map.update)',
                )))()
          : update(_valueCodec.fromStored(storedValue));
      await _box.put(rawKey.value, _valueCodec.toStorable(updatedValue));
      _observer?.onWritten(name, semanticKey, updatedValue);

      return updatedValue;
    });
  }

  /// Deletes [rawKey]. No gate: deletes cannot corrupt (hive no-ops absent keys before writing any
  /// frame, and a bad key was never admitted by the write gate).
  Task<Unit> delete(RawKey rawKey, Object semanticKey) => _guard('delete', () async {
    await _box.delete(rawKey.value);
    _observer?.onDeleted(name, semanticKey);

    return unit;
  });

  /// Deletes [rawKeysToDelete] in one batch, dispatching one event per [semanticKeys] entry.
  /// Parallel lists, both built by the façade in one traversal.
  Task<Unit> deleteAll(List<RawKey> rawKeysToDelete, List<Object> semanticKeys) {
    final unwrappedKeys = [for (final rawKey in rawKeysToDelete) rawKey.value];

    return _guard('deleteAll', () async {
      await _box.deleteAll(unwrappedKeys);
      for (final semanticKey in semanticKeys) {
        _observer?.onDeleted(name, semanticKey);
      }

      return unit;
    });
  }

  /// Removes every entry.
  Task<Unit> clear() => _guard('clear', () async {
    await _box.clear();
    _observer?.onCleared(name);

    return unit;
  });

  /// hive's own change stream, narrowed to [key] when given. Raw because the façade owns the key codec,
  /// and typing it here would only be rebuilt there.
  Stream<BoxEvent> watchRaw({RawKey? key}) => _box.watch(key: key?.value);

  /// Flushes pending writes to disk.
  Task<Unit> flush() => _guard('flush', () async {
    await _box.flush();

    return unit;
  });

  /// Compacts the box file.
  Task<Unit> compact() => _guard('compact', () async {
    await _box.compact();

    return unit;
  });

  /// Closes the box; terminal for this handle.
  Task<Unit> close() => _guard('close', () async {
    await _box.close();
    _observer?.onClosed(name);

    return unit;
  });

  /// Deletes the box from disk; terminal for this handle.
  Task<Unit> deleteFromDisk() => _guard('deleteFromDisk', () async {
    await _box.deleteFromDisk();
    _observer?.onDeletedFromDisk(name);

    return unit;
  });

  /// Wraps an effect into a [Task], reporting failures to the observer before rethrowing.
  Task<R> _guard<R>(String operation, Future<R> Function() effect) => Task(() async {
    try {
      return await effect();
    } on Object catch (error, stackTrace) {
      _observer?.onOperationError(name, operation, error, stackTrace);
      rethrow;
    }
  });
}
