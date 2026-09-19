/// Copies [values] into a fixed-length list, because hive won't take a non-`List` iterable and the copy
/// keeps later consumer-side edits out of hive's cache. The unmodifiable view on the read side closes
/// the same hole from the other end.
List<E> materialisedCopyOf<E extends Object>(Iterable<E> values) =>
    List<E>.of(values, growable: false);

/// A fresh copy of [values] without the element at [index]. The caller has already found the index.
List<E> copyWithoutIndex<E extends Object>(List<E> values, int index) => [
  ...values.take(index),
  ...values.skip(index + 1),
];
