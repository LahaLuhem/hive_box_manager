import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';

import '../codec/key_codec.dart';
import '../event/typed_box_event.dart';
import '../observer/box_observer.dart';
import 'raw_key_gate.dart';
import 'value_codec.dart';

/// The eager CRUD engine: every eager façade delegates here, so CRUD is written exactly once.
///
/// Policies enter by injection (key codec, value codec, observer); the engine owns the
/// mechanics: encode, gate, hive, decode, dispatch. Sync reads are legal by construction: an
/// eager engine only ever exists around an already-open box (the façades' async openers
/// guarantee it), and `close()` / `deleteFromDisk()` are terminal, after which operations
/// surface the engine's own already-closed error (tier 3: no wrapper pre-check).
///
/// Precondition violations (a codec emitting a non-storable raw key) throw synchronously at the
/// call site, before any [Task] is built: fail at the site, not at `.run()`.
final class EagerCrudEngine<T extends Object, K extends Object> {
  /// Wires the engine around an open [box].
  EagerCrudEngine({
    required Box<Object?> box,
    required KeyCodec<K> keyCodec,
    required ValueCodec<T> valueCodec,
    BoxObserver? observer,
  }) : _box = box,
       _keyCodec = keyCodec,
       _valueCodec = valueCodec,
       _observer = observer;

  final Box<Object?> _box;
  final KeyCodec<K> _keyCodec;
  final ValueCodec<T> _valueCodec;
  final BoxObserver? _observer;

  /// The underlying box name: the observer correlation handle.
  String get name => _box.name;

  /// Number of stored entries (keys live in memory on both axes).
  int get length => _box.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _box.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _box.isNotEmpty;

  /// The stored keys, decoded lazily.
  Iterable<K> get keys => _box.keys.map((rawKey) => _keyCodec.decode(rawKey as Object));

  /// The stored values, decoded lazily; dispatches one read-all event at call time.
  Iterable<T> get values {
    _observer?.onReadAll(name, _box.length);

    return _box.values.map((storedValue) => _valueCodec.fromStored(storedValue!));
  }

  /// Reads [key], `None` when absent.
  Option<T> get(K key) {
    final storedValue = _box.get(_keyCodec.encode(key));
    _observer?.onRead(name, key, storedValue);

    return storedValue == null ? const None() : Some(_valueCodec.fromStored(storedValue));
  }

  /// Reads [key], falling back to [fallback] when absent.
  T getOr(K key, T fallback) => get(key).getOrElse(() => fallback);

  /// Whether [key] is stored right now.
  bool contains(K key) => _box.containsKey(_keyCodec.encode(key));

  /// Writes [value] under [key].
  Task<Unit> put(K key, T value) {
    final rawKey = _keyCodec.encode(key);
    ensureStorableRawKey(rawKey);

    return _guard('put', () async {
      await _box.put(rawKey, _valueCodec.toStorable(value));
      _observer?.onWritten(name, key, value);

      return unit;
    });
  }

  /// Writes every entry of [entries] in one batch.
  Task<Unit> putAll(Map<K, T> entries) {
    // Encoded and gated at call time (fail fast, before the Task exists), so a bad key means
    // nothing gets written.
    final rawEntries = entries.map((key, value) {
      final rawKey = _keyCodec.encode(key);
      ensureStorableRawKey(rawKey);

      return MapEntry(rawKey, _valueCodec.toStorable(value));
    });

    return _guard('putAll', () async {
      await _box.putAll(rawEntries);
      _observer?.onWrittenAll(name, rawEntries.length);

      return unit;
    });
  }

  /// Rewrites [key] through [update], mirroring `Map.update`: absent + no [ifAbsent] is an
  /// [ArgumentError] inside the task, evaluated when it runs.
  Task<T> update(K key, T Function(T value) update, {T Function()? ifAbsent}) {
    final rawKey = _keyCodec.encode(key);
    ensureStorableRawKey(rawKey);

    return _guard('update', () async {
      final storedValue = _box.get(rawKey);
      final updatedValue = storedValue == null
          ? (ifAbsent ??
                (() => throw ArgumentError.value(
                  key,
                  'key',
                  'absent, and no ifAbsent was given (mirrors Map.update)',
                )))()
          : update(_valueCodec.fromStored(storedValue));
      await _box.put(rawKey, _valueCodec.toStorable(updatedValue));
      _observer?.onWritten(name, key, updatedValue);

      return updatedValue;
    });
  }

  /// Deletes [key]. No gate: deletes cannot corrupt (hive no-ops absent keys before writing any
  /// frame, and a bad key was never admitted by the write gate).
  Task<Unit> delete(K key) {
    final rawKey = _keyCodec.encode(key);

    return _guard('delete', () async {
      await _box.delete(rawKey);
      _observer?.onDeleted(name, key);

      return unit;
    });
  }

  /// Deletes every key in [keys] in one batch.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Materialised: encoded once at call time (fail-fast contract), re-used for dispatch.
    final keyList = keys.toList(growable: false);
    final rawKeys = keyList.map(_keyCodec.encode).toList(growable: false);

    return _guard('deleteAll', () async {
      await _box.deleteAll(rawKeys);
      for (final key in keyList) {
        _observer?.onDeleted(name, key);
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

  /// Typed change stream; [key] filters to one key. Values are non-null even on deletes: eager
  /// hive delivers the deleted value from its cache (pinned).
  Stream<TypedBoxEvent<T, K>> watch({K? key}) => _box
      .watch(key: key == null ? null : _keyCodec.encode(key))
      .map(
        (event) => TypedBoxEvent(
          key: _keyCodec.decode(event.key as Object),
          value: _valueCodec.fromStored(event.value as Object),
          deleted: event.deleted,
        ),
      );

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
