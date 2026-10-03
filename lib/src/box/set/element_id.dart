/// What a set box tells [T] elements apart by: [idOf], or the element itself for value types.
Object Function(T element) resolveIdOf<T extends Object>(Object Function(T element)? idOf) {
  if (idOf == null) {
    assert(
      _isValueType<T>(),
      'No idOf for a set of $T. A restart hands back fresh objects, so only String, num, bool and '
      'enum elements can be told apart without one. Pass idOf:.',
    );

    return (element) => element;
  }

  return (element) {
    final id = idOf(element);
    assert(
      id is String || id is num || id is bool || id is Enum,
      'idOf returned a ${id.runtimeType}. Return a String, num, bool or enum.',
    );

    return id;
  };
}

/// [elements] with the first one per id, as a plain set so it compares the same after a restart.
Set<T> dedupedById<T extends Object>(Iterable<T> elements, Object Function(T element) idOf) {
  final firstPerId = <Object, T>{};
  for (final element in elements) {
    firstPerId[idOf(element)] ??= element;
  }

  final deduped = Set<T>.of(firstPerId.values);
  assert(
    deduped.length == firstPerId.length,
    'Elements with different ids are == to each other, so the set would merge them. Make == and '
    'idOf agree.',
  );

  return deduped;
}

// A type can't be tested directly, but an empty list of it can.
bool _isValueType<T>() {
  final probe = <T>[];

  return probe is List<String> || probe is List<num> || probe is List<bool> || probe is List<Enum>;
}
