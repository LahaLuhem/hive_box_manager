import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '/src/core/restart_safe.dart';

/// What a set or list box tells [T] elements apart by: [idOf], or the element itself.
@internal
Object Function(T element) resolveIdOf<T extends Object>(Object Function(T element)? idOf) {
  if (idOf == null) {
    return (element) {
      assert(
        isRestartSafeValue(element),
        '${element.runtimeType} compares by identity, so the copies a restart hands back never '
        'match it. Pass idOf:, or give it its own == and hashCode.',
      );

      return element;
    };
  }

  return (element) {
    final id = idOf(element);
    assert(
      isRestartSafeValue(id),
      'idOf returned a ${id.runtimeType}, which compares by identity. Return something with its own '
      '==, like a String or a record.',
    );

    return id;
  };
}

/// [elements] with the first one per id, as a plain set so it compares the same after a restart.
@internal
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
@internal
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
