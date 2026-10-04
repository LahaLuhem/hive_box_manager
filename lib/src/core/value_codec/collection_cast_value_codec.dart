import 'dart:collection';

import 'element_type_check.dart';
import 'value_codec.dart';

/// hive reads a list of a custom type back as `List<dynamic>`, so this casts it back on the way out.
///
/// The result is wrapped unmodifiable on top, which costs nothing: an eager get aliases hive's own cache,
/// so a view keeps consumers out of it without copying on every read.
final class CollectionCastValueCodec<E extends Object>() implements ValueCodec<List<E>> {
  /// Trips a development assert for an [E] that can't read back typed after a restart.
  this {
    assertRestorableElementType<E>();
  }

  @override
  Object toStorable(List<E> value) => value;

  @override
  List<E> fromStored(Object storedValue) {
    final storedList = storedValue as List<Object?>;
    // Written this session, or one of hive's typed primitive lists: nothing to check or cast.
    if (storedList is List<E>) return UnmodifiableListView(storedList);

    checkElementTypes<E>(storedList);

    return UnmodifiableListView(storedList.cast<E>());
  }
}
