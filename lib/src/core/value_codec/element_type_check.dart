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

/// Whether a stored collection of [E] still reads back as one after a restart. The cast only reaches
/// the outer collection, so an [E] that's itself a collection has to be a shape hive keeps typed.
bool isRestorableElementType<E extends Object>() {
  // A type can't be tested directly, but an empty list of it can.
  final probe = <E>[];
  if (probe is! List<Iterable<Object?>> && probe is! List<Map<Object?, Object?>>) return true;

  // Exact shapes only: hive hands an Int32List back as a plain List<int>, for one.
  return _isExactly<E, List<int>>() ||
      _isExactly<E, List<double>>() ||
      _isExactly<E, List<bool>>() ||
      _isExactly<E, List<String>>() ||
      _isExactly<E, Set<int>>() ||
      _isExactly<E, Set<double>>() ||
      _isExactly<E, Set<String>>() ||
      _isExactly<E, Uint8List>();
}

/// Trips a development assert when [E] fails [isRestorableElementType].
void assertRestorableElementType<E extends Object>() {
  assert(
    isRestorableElementType<E>(),
    '$E elements come back from disk untyped, so every read after a restart would throw. Only lists '
    'of int, double, bool or String, sets of int, double or String, and Uint8List nest safely. Wrap '
    'anything else in a type with its own adapter.',
  );
}

bool _isExactly<A, B>() => <A>[] is List<B> && <B>[] is List<A>;
