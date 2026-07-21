import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';

import '../../codec/key/key_codec.dart';
import '../../event/lazy_typed_box_event.dart';
import '../../observer/box_observer.dart';
import '../raw_key_gate.dart';
import '../value_codec/value_codec.dart';

/// The lazy CRUD engine: every lazy façade delegates here, so CRUD is written exactly once.
///
/// Constructs synchronously and auto-opens **single-flight** on first use: the first operation
/// triggers the open, every concurrent caller awaits the same future, and a failed open resets
/// the memo so a later operation can retry. `ensureInitialised()` exposes the warm-up
/// compositionally. The 0.0.x init-forgotten crash is unrepresentable for effects; the sync
/// inspectors ([length], [isEmpty], [isNotEmpty], [keys], [contains]) are the one carve-out:
/// they need the keystore, so before the first open they throw a [StateError] naming the fix.
///
/// `close()` / `deleteFromDisk()` are terminal: the memo stays resolved on purpose, and later
/// operations surface the engine's own already-closed error (tier 3: no wrapper pre-check).
/// Precondition violations (a codec emitting a non-storable raw key) throw synchronously at the
/// call site, before any [Task] is built.
final class LazyCrudEngine<T extends Object, K extends Object> {
  /// Wires the engine around [_openBox], which is invoked at most once (single-flight).
  LazyCrudEngine({
    required this._boxName,
    required this._openBox,
    required this._keyCodec,
    required this._valueCodec,
    this._observer,
  });

  final String _boxName;
  final Future<LazyBox<Object?>> Function() _openBox;
  final KeyCodec<K> _keyCodec;
  final ValueCodec<T> _valueCodec;
  final BoxObserver? _observer;

  Future<LazyBox<Object?>>? _boxFuture;
  LazyBox<Object?>? _box;

  /// The box name: the observer correlation handle (available before the box opens).
  String get name => _boxName;

  /// Warms the box up compositionally; any effect does the same implicitly.
  Task<Unit> ensureInitialised() => Task(() async {
    await _obtainBox();

    return unit;
  });

  /// Number of stored entries (the keystore lives in memory once open).
  int get length => _requireOpened.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _requireOpened.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _requireOpened.isNotEmpty;

  /// The stored keys, decoded lazily.
  Iterable<K> get keys => _requireOpened.keys.map((rawKey) => _keyCodec.decode(rawKey as Object));

  /// Whether [key] is stored right now.
  bool contains(K key) => _requireOpened.containsKey(_keyCodec.encode(key));

  /// Reads [key], `None` when absent.
  TaskOption<T> get(K key) => TaskOption(
    () => _guarded('get', () async {
      final box = await _obtainBox();
      final storedValue = await box.get(_keyCodec.encode(key));
      _observer?.onRead(name, key, storedValue);

      return storedValue == null ? const None() : Some(_valueCodec.fromStored(storedValue));
    }),
  );

  /// Reads [key], falling back to [fallback] when absent.
  Task<T> getOr(K key, T fallback) => Task(
    () => _guarded('getOr', () async {
      final box = await _obtainBox();
      final storedValue = await box.get(_keyCodec.encode(key));
      _observer?.onRead(name, key, storedValue);

      return storedValue == null ? fallback : _valueCodec.fromStored(storedValue);
    }),
  );

  /// Reads every value; materialised, so completion means every disk read already happened.
  Task<List<T>> values() => Task(
    () => _guarded('values', () async {
      final box = await _obtainBox();
      _observer?.onReadAll(name, box.length);
      final storedValues = await box.keys.map(box.get).wait;

      return storedValues
          .map((storedValue) => _valueCodec.fromStored(storedValue!))
          .toList(growable: false);
    }),
  );

  /// Writes [value] under [key].
  Task<Unit> put(K key, T value) {
    final rawKey = _keyCodec.encode(key);
    ensureStorableRawKey(rawKey);

    return Task(
      () => _guarded('put', () async {
        final box = await _obtainBox();
        await box.put(rawKey, _valueCodec.toStorable(value));
        _observer?.onWritten(name, key, value);

        return unit;
      }),
    );
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

    return Task(
      () => _guarded('putAll', () async {
        final box = await _obtainBox();
        await box.putAll(rawEntries);
        _observer?.onWrittenAll(name, rawEntries.length);

        return unit;
      }),
    );
  }

  /// Rewrites [key] through [update], mirroring `Map.update`: absent + no [ifAbsent] is an
  /// [ArgumentError] inside the task, evaluated when it runs.
  Task<T> update(K key, T Function(T value) update, {T Function()? ifAbsent}) {
    final rawKey = _keyCodec.encode(key);
    ensureStorableRawKey(rawKey);

    return Task(
      () => _guarded('update', () async {
        final box = await _obtainBox();
        final storedValue = await box.get(rawKey);
        final updatedValue = storedValue == null
            ? (ifAbsent ??
                  (() => throw ArgumentError.value(
                    key,
                    'key',
                    'absent, and no ifAbsent was given (mirrors Map.update)',
                  )))()
            : update(_valueCodec.fromStored(storedValue));
        await box.put(rawKey, _valueCodec.toStorable(updatedValue));
        _observer?.onWritten(name, key, updatedValue);

        return updatedValue;
      }),
    );
  }

  /// Deletes [key]. No gate: deletes cannot corrupt (hive no-ops absent keys before writing any
  /// frame, and a bad key was never admitted by the write gate).
  Task<Unit> delete(K key) {
    final rawKey = _keyCodec.encode(key);

    return Task(
      () => _guarded('delete', () async {
        final box = await _obtainBox();
        await box.delete(rawKey);
        _observer?.onDeleted(name, key);

        return unit;
      }),
    );
  }

  /// Deletes every key in [keys] in one batch.
  Task<Unit> deleteAll(Iterable<K> keys) {
    // Materialised: encoded once at call time (fail-fast contract), re-used for dispatch.
    final keyList = keys.toList(growable: false);
    final rawKeys = keyList.map(_keyCodec.encode).toList(growable: false);

    return Task(
      () => _guarded('deleteAll', () async {
        final box = await _obtainBox();
        await box.deleteAll(rawKeys);
        for (final key in keyList) {
          _observer?.onDeleted(name, key);
        }

        return unit;
      }),
    );
  }

  /// Removes every entry.
  Task<Unit> clear() => Task(
    () => _guarded('clear', () async {
      final box = await _obtainBox();
      await box.clear();
      _observer?.onCleared(name);

      return unit;
    }),
  );

  /// Typed change stream; [key] filters to one key. Writes carry `Some`, deletes carry `None`:
  /// a lazy box retains no values, so the engine has nothing to attach on deletes (pinned).
  Stream<LazyTypedBoxEvent<T, K>> watch({K? key}) async* {
    final box = await _obtainBox();

    yield* box
        .watch(key: key == null ? null : _keyCodec.encode(key))
        .map(
          (event) => LazyTypedBoxEvent(
            key: _keyCodec.decode(event.key as Object),
            value: Option.fromNullable(event.value as Object?).map(_valueCodec.fromStored),
          ),
        );
  }

  /// Flushes pending writes to disk.
  Task<Unit> flush() => Task(
    () => _guarded('flush', () async {
      await (await _obtainBox()).flush();

      return unit;
    }),
  );

  /// Compacts the box file.
  Task<Unit> compact() => Task(
    () => _guarded('compact', () async {
      await (await _obtainBox()).compact();

      return unit;
    }),
  );

  /// Closes the box; terminal for this handle.
  Task<Unit> close() => Task(
    () => _guarded('close', () async {
      await (await _obtainBox()).close();
      _observer?.onClosed(name);

      return unit;
    }),
  );

  /// Deletes the box from disk; terminal for this handle.
  Task<Unit> deleteFromDisk() => Task(
    () => _guarded('deleteFromDisk', () async {
      await (await _obtainBox()).deleteFromDisk();
      _observer?.onDeletedFromDisk(name);

      return unit;
    }),
  );

  /// Single-flight auto-open: assigns the memo synchronously so every concurrent first caller
  /// shares one open; a failed open clears it so retry is possible.
  Future<LazyBox<Object?>> _obtainBox() => _boxFuture ??= _openBox()
      .then((box) {
        _box = box;
        _observer?.onOpened(name);

        return box;
      })
      .onError<Object>((error, stackTrace) {
        _boxFuture = null;
        _observer?.onOperationError(name, 'open', error, stackTrace);
        Error.throwWithStackTrace(error, stackTrace);
      });

  LazyBox<Object?> get _requireOpened =>
      _box ??
      (throw StateError(
        'LazyBox "$_boxName" is not open yet: the sync inspectors (length / isEmpty / '
        'isNotEmpty / keys / contains) need the keystore in memory. Run any effect or '
        'ensureInitialised() first.',
      ));

  /// Runs an effect, reporting failures to the observer before rethrowing.
  Future<R> _guarded<R>(String operation, Future<R> Function() effect) async {
    try {
      return await effect();
    } on Object catch (error, stackTrace) {
      _observer?.onOperationError(name, operation, error, stackTrace);
      rethrow;
    }
  }
}
