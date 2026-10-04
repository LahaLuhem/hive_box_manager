/// @docImport 'collection_cast_value_codec.dart';
library;

import 'dart:collection';

import 'element_type_check.dart';
import 'value_codec.dart';

/// [CollectionCastValueCodec] for sets, which hive reads back as `Set<dynamic>` unless they hold
/// `int`, `double` or `String`.
final class const SetCastValueCodec<E extends Object>() implements ValueCodec<Set<E>> {
  /// Const so engines can default to it without an allocation per box.
  this;

  @override
  Object toStorable(Set<E> value) => value;

  @override
  Set<E> fromStored(Object storedValue) {
    final storedSet = storedValue as Set<Object?>;
    if (storedSet is Set<E>) return UnmodifiableSetView(storedSet);

    checkElementTypes<E>(storedSet);

    return UnmodifiableSetView(storedSet.cast<E>());
  }
}
