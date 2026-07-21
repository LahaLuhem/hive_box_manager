/// @docImport 'collection_cast_value_codec.dart';
/// @docImport 'identity_value_codec.dart';
library;

/// Internal read/write-boundary transform between consumer values [T] and what hive stores.
///
/// This seam exists so `dynamic` never reaches the public surface: boxes open
/// `Object?`-parameterised (hive reifies collections from disk as `List<dynamic>` regardless of the write-side type),
/// and this codec restores [T] at the boundary. Internal on purpose: a public value codec is the one
/// place consumers could launder `dynamic` back in, so it goes public only if a second genuine
/// implementation earns it (the 1.x seam review). Shipped implementations: [IdentityValueCodec] and
/// [CollectionCastValueCodec].
abstract interface class ValueCodec<T extends Object> {
  /// Adapts [value] for storage; the engine writes the result verbatim.
  Object toStorable(T value);

  /// Restores the consumer-facing [T] from what hive handed back.
  T fromStored(Object storedValue);
}
