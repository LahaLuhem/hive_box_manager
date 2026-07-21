import 'dart:collection';

import 'value_codec.dart';

/// The collection cast (upstream issue #150): disk reads reify as `List<dynamic>` whatever the
/// write-side element type, so element typing is restored with a cast view at the read boundary.
///
/// The result is additionally wrapped unmodifiable, zero-copy: eager gets alias the box's own cache,
/// which is never mutated in place, so a view locks consumers out of the cache without paying a copy
/// per read (the scenario call CODESTYLE's unmodifiable-collections idiom sanctions).
final class CollectionCastValueCodec<E extends Object> implements ValueCodec<List<E>> {
  /// Const so engines can default to it without an allocation per box.
  const CollectionCastValueCodec();

  @override
  Object toStorable(List<E> value) => value;

  @override
  List<E> fromStored(Object storedValue) =>
      UnmodifiableListView((storedValue as List<Object?>).cast<E>());
}
