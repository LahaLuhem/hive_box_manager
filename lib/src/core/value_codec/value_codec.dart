/// @docImport 'collection_cast_value_codec.dart';
/// @docImport 'identity_value_codec.dart';
library;

/// Internal read/write-boundary transform between consumer values [T] and what hive stores.
///
/// This seam is how `dynamic` is kept off the public surface. Boxes open as `Object?` and hive reads
/// collections back as `List<dynamic>`, so the codec puts [T] back at the boundary. It stays internal
/// because a public value codec is exactly where someone could launder `dynamic` in again.
abstract interface class ValueCodec<T extends Object> {
  /// Adapts [value] for storage. The engine writes the result as is.
  Object toStorable(T value);

  /// Restores the consumer-facing [T] from what hive handed back.
  T fromStored(Object storedValue);
}
