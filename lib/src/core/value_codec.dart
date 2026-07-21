import 'dart:collection';

/// Internal read/write-boundary transform between consumer values [T] and what hive stores.
///
/// This seam exists so `dynamic` never reaches the public surface: boxes open
/// `Object?`-parameterised (hive reifies collections from disk as `List<dynamic>` regardless of
/// the write-side type), and this codec restores [T] at the boundary. Internal on purpose: a
/// public value codec is the one place consumers could launder `dynamic` back in, so it goes
/// public only if a second genuine implementation earns it (the 1.x seam review).
abstract interface class ValueCodec<T extends Object> {
  /// Adapts [value] for storage; the engine writes the result verbatim.
  Object toStorable(T value);

  /// Restores the consumer-facing [T] from what hive handed back.
  T fromStored(Object storedValue);
}

/// Pass-through codec for plainly-typed boxes: hive's adapters already round-trip [T].
final class IdentityValueCodec<T extends Object> implements ValueCodec<T> {
  /// Const so engines can default to it without an allocation per box.
  const IdentityValueCodec();

  @override
  Object toStorable(T value) => value;

  @override
  T fromStored(Object storedValue) => storedValue as T;
}

/// The collection cast (upstream issue #150): disk reads reify as `List<dynamic>` whatever the
/// write-side element type, so element typing is restored with a cast view at the read
/// boundary.
///
/// The result is additionally wrapped unmodifiable, zero-copy: eager gets alias the box's own
/// cache, which is never mutated in place, so a view locks consumers out of the cache without
/// paying a copy per read (the scenario call CODESTYLE's unmodifiable-collections idiom
/// sanctions).
final class CollectionCastValueCodec<E extends Object> implements ValueCodec<List<E>> {
  /// Const so engines can default to it without an allocation per box.
  const CollectionCastValueCodec();

  @override
  Object toStorable(List<E> value) => value;

  @override
  List<E> fromStored(Object storedValue) =>
      UnmodifiableListView((storedValue as List<Object?>).cast<E>());
}
