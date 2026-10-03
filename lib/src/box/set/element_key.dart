/// What a set box tells [T] elements apart by: [keyOf], or the element itself for value types.
Object Function(T element) resolveKeyOf<T extends Object>(Object Function(T element)? keyOf) {
  if (keyOf == null) {
    assert(
      _isValueType<T>(),
      'No keyOf for a set of $T. A restart hands back fresh objects, so only String, num, bool and '
      'enum elements can be told apart without one. Pass keyOf:.',
    );

    return (element) => element;
  }

  return (element) {
    final key = keyOf(element);
    assert(
      key is String || key is num || key is bool || key is Enum,
      'keyOf returned a ${key.runtimeType}. Return a String, num, bool or enum.',
    );

    return key;
  };
}

/// [elements] with the first one per key, as a plain set so it compares the same after a restart.
Set<T> dedupedByKey<T extends Object>(Iterable<T> elements, Object Function(T element) keyOf) {
  final firstPerKey = <Object, T>{};
  for (final element in elements) {
    firstPerKey[keyOf(element)] ??= element;
  }

  final deduped = Set<T>.of(firstPerKey.values);
  assert(
    deduped.length == firstPerKey.length,
    'Elements with different keys are == to each other, so the set would merge them. Make == and '
    'keyOf agree.',
  );

  return deduped;
}

// A type can't be tested directly, but an empty list of it can.
bool _isValueType<T>() {
  final probe = <T>[];

  return probe is List<String> || probe is List<num> || probe is List<bool> || probe is List<Enum>;
}
