/// @docImport 'collection_cast_value_codec.dart';
library;

import 'dart:collection';

import 'element_type_check.dart';
import 'value_codec.dart';

/// [CollectionCastValueCodec] for maps, which hive reads back as `Map<dynamic, dynamic>` whatever they
/// hold.
final class MapCastValueCodec<MK extends Object, MV extends Object>()
    implements ValueCodec<Map<MK, MV>> {
  /// Trips a development assert for an [MV] that can't read back typed after a restart.
  this {
    assertRestorableElementType<MV>();
  }

  @override
  Object toStorable(Map<MK, MV> value) => value;

  @override
  Map<MK, MV> fromStored(Object storedValue) {
    final storedMap = storedValue as Map<Object?, Object?>;
    // Written this session: nothing to check or cast. A map read from disk never comes back typed.
    if (storedMap is Map<MK, MV>) return UnmodifiableMapView(storedMap);

    checkEntryTypes<MK, MV>(storedMap);

    return UnmodifiableMapView(storedMap.cast<MK, MV>());
  }
}
