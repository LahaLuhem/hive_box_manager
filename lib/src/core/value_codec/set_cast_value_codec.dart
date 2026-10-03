/// @docImport 'collection_cast_value_codec.dart';
library;

import 'dart:collection';

import 'value_codec.dart';

/// [CollectionCastValueCodec] for sets, which hive reads back as `Set<dynamic>` unless they hold
/// `int`, `double` or `String`.
final class SetCastValueCodec<E extends Object> implements ValueCodec<Set<E>> {
  /// Const so engines can default to it without an allocation per box.
  const new();

  @override
  Object toStorable(Set<E> value) => value;

  @override
  Set<E> fromStored(Object storedValue) =>
      UnmodifiableSetView((storedValue as Set<Object?>).cast<E>());
}
