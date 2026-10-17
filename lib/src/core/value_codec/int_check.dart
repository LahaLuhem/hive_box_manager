import 'dart:typed_data';

import '../exact_int_gate.dart';

/// Throws when a value holds an int hive would change.
typedef IntCheck = void Function(Object? value);

/// The check a write runs on a [T] before hive stores it, or null when a [T] can't hold an int.
IntCheck? intCheckFor<T extends Object>() => _checksFor<T>().one;

/// [intCheckFor] for each element of a list or set of [E].
IntCheck? elementsCheckFor<E extends Object>() => _checksFor<E>().each;

/// [intCheckFor] for each key and value of a map of [MK] to [MV]. A key gets the key gate's error.
IntCheck? entriesCheckFor<MK extends Object, MV extends Object>() {
  final checksKeys = intCheckFor<MK>() != null;
  final valueCheck = intCheckFor<MV>();
  if (!checksKeys && valueCheck == null) return null;

  return (map) => (map! as Map<Object?, Object?>).forEach((key, value) {
    if (checksKeys && key is int) ensureExactIntKey(key);
    valueCheck?.call(value);
  });
}

typedef _Checks = ({IntCheck? one, IntCheck? each});

const _Checks _noInt = (one: null, each: null);
const _Checks _anInt = (one: _checkInt, each: _checkEachInt);
const _Checks _ints = (one: _checkEachInt, each: _checkEachIntCollection);
// Walking a collection walks each element.
const _Checks _anything = (one: _checkDeep, each: _checkDeep);

_Checks _checksFor<T extends Object>() {
  // A type can't be tested directly, but an empty list of it can.
  final probe = <T>[];
  final isObject = <Object>[] is List<T>;
  if (isObject) return _anything;
  if (probe is List<Iterable<Object?>> || probe is List<Map<Object?, Object?>>) {
    // Bytes, strings, doubles and bools are never ints.
    if (probe is List<Uint8List> ||
        probe is List<Iterable<String>> ||
        probe is List<Iterable<double>> ||
        probe is List<Iterable<bool>>) {
      return _noInt;
    }

    return probe is List<Iterable<int>> ? _ints : _anything;
  }

  return <int>[] is List<T> ? _anInt : _noInt;
}

// Inlining it takes about a third off checking a list of ints.
@pragma('vm:prefer-inline')
void _checkInt(Object? value) {
  if (value is int) ensureExactIntValue(value);
}

// forEach over a for-in, since the collection's own loop runs about twice as fast.
void _checkEachInt(Object? values) => (values! as Iterable<Object?>).forEach(_checkInt);

void _checkEachIntCollection(Object? collections) =>
    (collections! as Iterable<Object?>).forEach(_checkEachInt);

/// Leaves first, since a decoded JSON value is mostly strings and numbers. Map keys too, since 2 that
/// hive can't tell apart would merge.
void _checkDeep(Object? value) {
  if (value is String) return;
  if (value is int) {
    ensureExactIntValue(value);
  } else if (value is List<Object?>) {
    for (var i = 0; i < value.length; i++) {
      final element = value[i];
      if (element is! String) _checkDeep(element);
    }
  } else if (value is Map<Object?, Object?>) {
    value.forEach(_checkDeepEntry);
  } else if (value is Set<Object?>) {
    value.forEach(_checkDeep);
  }
}

void _checkDeepEntry(Object? key, Object? value) {
  if (key is! String) _checkDeep(key);
  if (value is! String) _checkDeep(value);
}
