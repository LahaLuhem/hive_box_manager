import 'dart:typed_data';

import 'package:collection/collection.dart';

/// Checked up front so a wrong element fails at the read, where the engine can name the key, and not
/// later wherever the list ends up being used.
void checkElementTypes<E extends Object>(Iterable<Object?> elements) {
  if (elements.every((element) => element is E)) return;

  // The cast is what throws, and its error names both types.
  elements.firstWhere((element) => element is! E)! as E;
}

/// [checkElementTypes] for a map, keys and values together in one pass over its entries.
void checkEntryTypes<K extends Object, V extends Object>(Map<Object?, Object?> map) {
  bool isTyped(MapEntry<Object?, Object?> entry) => entry.key is K && entry.value is V;
  if (map.entries.every(isTyped)) return;

  // The casts are what throw, and the error names both types.
  final offender = map.entries.whereNot(isTyped).first;
  offender.key! as K;
  offender.value! as V;
}

/// Whether a stored [T] still reads back as one after a restart, on its own or inside a collection.
bool isRestorableType<T extends Object>() {
  // A type can't be tested directly, but an empty list of it can.
  final probe = <T>[];
  final isCollection = probe is List<Iterable<Object?>> || probe is List<Map<Object?, Object?>>;

  // Exact shapes only: hive hands an Int32List back as a plain List<int>, for one.
  return !isCollection ||
      _isExactly<T, List<int>>() ||
      _isExactly<T, List<double>>() ||
      _isExactly<T, List<bool>>() ||
      _isExactly<T, List<String>>() ||
      _isExactly<T, Set<int>>() ||
      _isExactly<T, Set<double>>() ||
      _isExactly<T, Set<String>>() ||
      _isExactly<T, Uint8List>() ||
      // Untyped to begin with, which is exactly what hive rebuilds.
      _isExactly<T, List<Object?>>() ||
      _isExactly<T, Set<Object?>>() ||
      _isExactly<T, Map<Object?, Object?>>();
}

/// Trips a development assert when [E] fails [isRestorableType].
void assertRestorableElementType<E extends Object>() {
  assert(
    isRestorableType<E>(),
    '$E elements come back from disk untyped, so every read after a restart would throw. Only lists '
    'of int, double, bool or String, sets of int, double or String, Uint8List, and lists, sets and '
    'maps of dynamic nest safely. Wrap anything else in a type with its own adapter.',
  );
}

/// [assertRestorableElementType] for a box's whole value.
void assertRestorableValueType<T extends Object>() {
  assert(
    isRestorableType<T>(),
    "$T doesn't come back from disk as itself, so every read after a restart would throw. Store a "
    'collection in a ListBox, SetBox or MapBox, or wrap it in a type with its own adapter.',
  );
}

bool _isExactly<A, B>() => <A>[] is List<B> && <B>[] is List<A>;
