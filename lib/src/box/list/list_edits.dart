/// Materialises [values] into a fixed-length private copy: hive rejects non-`List` iterables at
/// write time (pinned), and the copy keeps later consumer-side mutations out of hive's eager
/// cache. The read side pairs this with the unmodifiable cast view, closing the aliasing hole
/// from both directions.
List<E> materialisedCopyOf<E extends Object>(Iterable<E> values) =>
    List<E>.from(values, growable: false);

/// A fresh copy of [values] without the element at [index]: the `List.remove` shape, with the
/// first-occurrence index already computed by the caller.
List<E> copyWithoutIndex<E extends Object>(List<E> values, int index) => [
  ...values.take(index),
  ...values.skip(index + 1),
];
