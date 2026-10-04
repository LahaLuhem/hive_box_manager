import 'package:collection/collection.dart';

import '/src/core/restart_safe.dart';

/// What a set box tells [T] elements apart by: [idOf], or the element itself for value types.
Object Function(T element) resolveIdOf<T extends Object>(Object Function(T element)? idOf) {
  if (idOf == null) {
    assert(
      isRestartSafeType<T>(),
      'No idOf for a set of $T. A restart hands back fresh objects, so only String, num, bool and '
      'enum elements can be told apart without one. Pass idOf:.',
    );

    return (element) => element;
  }

  return (element) {
    final id = idOf(element);
    assert(
      isRestartSafeValue(id),
      'idOf returned a ${id.runtimeType}. Return a String, num, bool or enum.',
    );

    return id;
  };
}

/// [elements] with the first one per id, as a plain set so it compares the same after a restart.
Set<T> dedupedById<T extends Object>(Iterable<T> elements, Object Function(T element) idOf) {
  final firstPerId = _firstPerId(elements, idOf);
  final deduped = Set.of(firstPerId.values);
  assert(
    deduped.length == firstPerId.length,
    'Elements with different ids are == to each other, so the set would merge them. Make == and '
    'idOf agree.',
  );

  return deduped;
}

/// [stored] with each element [incoming] shares an id with replaced where it sits, and the rest of
/// [incoming] on the end.
Set<T> upsertedById<T extends Object>(
  Iterable<T> stored,
  Iterable<T> incoming,
  Object Function(T element) idOf,
) {
  final incomingById = _firstPerId(incoming, idOf);

  return dedupedById(
    // A replaced element already sits in place, so dedup drops its copy from the appended values.
    stored.map((element) => incomingById[idOf(element)] ?? element).followedBy(incomingById.values),
    idOf,
  );
}

Map<Object, T> _firstPerId<T extends Object>(
  Iterable<T> elements,
  Object Function(T element) idOf,
) => elements.groupFoldBy(idOf, (first, element) => first ?? element);
