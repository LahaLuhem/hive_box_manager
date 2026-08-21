import 'package:fpdart/fpdart.dart';
import 'package:hive_ce/hive.dart';

import '/src/observer/box_observer.dart';
import '../raw_key.dart';
import '../raw_key_gate.dart';
import '../undecodable_value_exception.dart';
import '../value_codec/value_codec.dart';

/// The lazy CRUD engine: every lazy façade delegates here, so CRUD is written exactly once.
///
/// Owns hive and the corruption gate; façades own their codecs. Keys arrive encoded as [RawKey],
/// with the semantic key alongside purely so observers hear what a consumer would recognise
/// (same split as the eager engine, and the same reason: see [RawKey]).
///
/// Constructs synchronously and auto-opens **single-flight** on first use: the first operation
/// triggers the open, every concurrent caller awaits the same future, and a failed open resets the
/// memo so a later operation can retry. `ensureInitialised()` exposes the warm-up compositionally.
/// The sync inspectors ([length], [isEmpty], [isNotEmpty], [rawKeys], [contains]) are the one
/// carve-out: they need the keystore, so before the first open they throw a [StateError].
///
/// `close()` / `deleteFromDisk()` are terminal: after a real close the memo stays resolved on
/// purpose, so later operations surface the engine's own already-closed error (tier 3). `close()`
/// before first use is a no-op (ratified rider): nothing opens just to be closed, `onClosed` still
/// dispatches, and the wrapper synthesises the same already-closed error afterwards because the
/// engine was never engaged. `deleteFromDisk()` before first use still opens then deletes: it must
/// reach storage. A codec emitting a non-storable raw key throws at the call site, before any
/// [Task] is built.
// ignore: public_member_api_docs -- a primary constructor has nowhere to hang a doc comment.
final class LazyCrudEngine<T extends Object>({
  required final String _boxName,
  required final Future<LazyBox<Object?>> Function() _openBox,
  required final ValueCodec<T> _valueCodec,
  final BoxObserver? _observer,
}) {
  Future<LazyBox<Object?>>? _boxFuture;
  LazyBox<Object?>? _box;
  var _wasClosedBeforeFirstUse = false;

  /// hive_ce's own post-close message (`BoxBaseImpl.checkOpen`), reused verbatim so a
  /// pre-first-use close surfaces indistinguishably from a real one.
  static const _alreadyClosedMessage = 'Box has already been closed.';

  /// The box name: the observer correlation handle (available before the box opens).
  String get name => _boxName;

  /// Number of stored entries (the keystore lives in memory once open).
  int get length => _requireOpened.length;

  /// Whether the box holds no entries.
  bool get isEmpty => _requireOpened.isEmpty;

  /// Whether the box holds at least one entry.
  bool get isNotEmpty => _requireOpened.isNotEmpty;

  /// The stored keys exactly as hive holds them. Façades decode; the query strategies scan.
  /// Same sync carve-out as [length]; the dual façades warm the box up before scanning.
  Iterable<Object> get rawKeys => _requireOpened.keys.map((rawKey) => rawKey as Object);

  /// Restores a stored value through the value codec, for façades assembling their watch events.
  T decodeStored(Object storedValue) => _valueCodec.fromStored(storedValue);

  /// Warms the box up compositionally; any effect does the same implicitly.
  Task<Unit> ensureInitialised() => Task(() async {
    await _obtainBox();

    return unit;
  });

  /// Whether [rawKey] is stored right now. No observer event, so no semantic key is needed.
  bool contains(RawKey rawKey) => _requireOpened.containsKey(rawKey.value);

  /// Reads [rawKey], `None` when absent. [semanticKey] is what observers hear.
  TaskOption<T> get(RawKey rawKey, Object semanticKey) => TaskOption(
    () => _guarded('get', () async {
      final box = await _obtainBox();
      final storedValue = await box.get(rawKey.value);
      _observer?.onRead(name, semanticKey, storedValue);

      return storedValue == null ? const None() : Some(_valueCodec.fromStored(storedValue));
    }),
  );

  /// Reads [rawKey], falling back to [fallback] when absent.
  Task<T> getOr(RawKey rawKey, Object semanticKey, T fallback) => Task(
    () => _guarded('getOr', () async {
      final box = await _obtainBox();
      final storedValue = await box.get(rawKey.value);
      _observer?.onRead(name, semanticKey, storedValue);

      return storedValue == null ? fallback : _valueCodec.fromStored(storedValue);
    }),
  );

  /// Reads every value; materialised, so completion means every disk read already happened.
  /// [semanticKeyOf] decodes a raw key for failure reports only.
  Task<List<T>> values(Object Function(Object rawKey) semanticKeyOf) => Task(
    () => _guarded('values', () async {
      final box = await _obtainBox();
      _observer?.onReadAll(name, box.length);

      return _readEach(
        box.keys.map((rawKey) => rawKey as Object).toList(growable: false),
        (rawKey) async => _valueCodec.fromStored((await box.get(rawKey))!),
        semanticKeyOf,
      );
    }),
  );

  /// Reads each of [rawKeys], `None` for any that vanished mid-scan. See [values] for [semanticKeyOf].
  Task<List<Option<T>>> getEach(
    List<RawKey> rawKeys,
    Object Function(Object rawKey) semanticKeyOf,
  ) => Task(
    () => _readEach(
      rawKeys.map((rawKey) => rawKey.value).toList(growable: false),
      (rawKey) => get(RawKey(rawKey), semanticKeyOf(rawKey)).run(),
      semanticKeyOf,
    ),
  );

  /// Awaits one [read] per raw key concurrently, rethrowing the first failure **in key order** as an
  /// [UndecodableValueException]. `.wait` would fold every outcome into one keyless error instead.
  Future<List<R>> _readEach<R>(
    List<Object> rawKeys,
    Future<R> Function(Object rawKey) read,
    Object Function(Object rawKey) semanticKeyOf,
  ) async {
    final failures = List<(Object, StackTrace)?>.filled(rawKeys.length, null);
    final values = await rawKeys.indexed.map((entry) async {
      final (index, rawKey) = entry;
      try {
        return await read(rawKey);
      } on Object catch (error, stackTrace) {
        failures[index] = (error, stackTrace);

        return null;
      }
    }).wait;

    for (final (index, failure) in failures.indexed) {
      if (failure == null) continue;

      final (error, stackTrace) = failure;
      Error.throwWithStackTrace(
        UndecodableValueException(boxName: name, key: semanticKeyOf(rawKeys[index]), cause: error),
        stackTrace,
      );
    }

    return values.cast<R>().toList(growable: false);
  }

  /// Writes [value] under [rawKey].
  Task<Unit> put(RawKey rawKey, Object semanticKey, T value) {
    ensureStorableRawKey(rawKey.value);

    return Task(
      () => _guarded('put', () async {
        final box = await _obtainBox();
        await box.put(rawKey.value, _valueCodec.toStorable(value));
        _observer?.onWritten(name, semanticKey, value);

        return unit;
      }),
    );
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

    return Task(
      () => _guarded('putAll', () async {
        final box = await _obtainBox();
        await box.putAll(storableEntries);
        _observer?.onWrittenAll(name, storableEntries.length);

        return unit;
      }),
    );
  }

  /// Rewrites [rawKey] through [update], mirroring `Map.update`: absent + no [ifAbsent] is an
  /// [ArgumentError] inside the task, evaluated when it runs.
  Task<T> update(
    RawKey rawKey,
    Object semanticKey,
    T Function(T value) update, {
    T Function()? ifAbsent,
  }) {
    ensureStorableRawKey(rawKey.value);

    return Task(
      () => _guarded('update', () async {
        final box = await _obtainBox();
        final storedValue = await box.get(rawKey.value);
        final updatedValue = storedValue == null
            ? (ifAbsent ??
                  (() => throw ArgumentError.value(
                    semanticKey,
                    'key',
                    'absent, and no ifAbsent was given (mirrors Map.update)',
                  )))()
            : update(_valueCodec.fromStored(storedValue));
        await box.put(rawKey.value, _valueCodec.toStorable(updatedValue));
        _observer?.onWritten(name, semanticKey, updatedValue);

        return updatedValue;
      }),
    );
  }

  /// Deletes [rawKey]. No gate: deletes cannot corrupt (hive no-ops absent keys before writing any
  /// frame, and a bad key was never admitted by the write gate).
  Task<Unit> delete(RawKey rawKey, Object semanticKey) => Task(
    () => _guarded('delete', () async {
      final box = await _obtainBox();
      await box.delete(rawKey.value);
      _observer?.onDeleted(name, semanticKey);

      return unit;
    }),
  );

  /// Deletes [rawKeysToDelete] in one batch, dispatching one event per [semanticKeys] entry.
  /// Parallel lists, both built by the façade in one traversal.
  Task<Unit> deleteAll(List<RawKey> rawKeysToDelete, List<Object> semanticKeys) {
    final unwrappedKeys = [for (final rawKey in rawKeysToDelete) rawKey.value];

    return Task(
      () => _guarded('deleteAll', () async {
        final box = await _obtainBox();
        await box.deleteAll(unwrappedKeys);
        for (final semanticKey in semanticKeys) {
          _observer?.onDeleted(name, semanticKey);
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

  /// hive's own change stream, narrowed to [key] when given; subscribing auto-opens like any
  /// effect. Raw because the façade owns the key codec, and typing it here would only be rebuilt
  /// there.
  Stream<BoxEvent> watchRaw({RawKey? key}) async* {
    final box = await _obtainBox();

    yield* box.watch(key: key?.value);
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

  /// Closes the box; terminal for this handle. Before first use nothing ever opened, so nothing
  /// closes and no open is paid (the ratified no-op): `onClosed` still dispatches, and the
  /// handle still turns terminal.
  Task<Unit> close() => Task(
    () => _guarded('close', () async {
      if (_boxFuture == null) {
        _wasClosedBeforeFirstUse = true;
        _observer?.onClosed(name);

        return unit;
      }

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
  /// shares one open; a failed open clears it so retry is possible. After a pre-first-use close
  /// it surfaces the engine-shaped already-closed error instead of opening.
  Future<LazyBox<Object?>> _obtainBox() {
    if (_wasClosedBeforeFirstUse) throw HiveError(_alreadyClosedMessage);

    return _boxFuture ??= _openBox()
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
  }

  LazyBox<Object?> get _requireOpened {
    if (_wasClosedBeforeFirstUse) throw HiveError(_alreadyClosedMessage);

    return _box ??
        (throw StateError(
          'LazyBox "$_boxName" is not open yet: the sync inspectors (length / isEmpty / '
          'isNotEmpty / keys / contains) need the keystore in memory. Run any effect or '
          'ensureInitialised() first.',
        ));
  }

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
