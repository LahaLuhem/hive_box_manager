import 'dart:collection';

import 'value_codec.dart';

/// Disk reads come back as `List<dynamic>` whatever the write-side element type, so this puts the element
/// typing back with a cast view at the read boundary.
///
/// The result is wrapped unmodifiable on top, which costs nothing: an eager get aliases hive's own cache,
/// so a view keeps consumers out of it without copying on every read.
final class CollectionCastValueCodec<E extends Object> implements ValueCodec<List<E>> {
  /// Const so engines can default to it without an allocation per box.
  const new();

  @override
  Object toStorable(List<E> value) => value;

  @override
  List<E> fromStored(Object storedValue) =>
      UnmodifiableListView((storedValue as List<Object?>).cast<E>());
}
