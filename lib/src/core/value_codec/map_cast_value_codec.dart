/// @docImport 'collection_cast_value_codec.dart';
library;

import 'dart:collection';

import '/src/core/restart_safe.dart';
import 'element_type_check.dart';
import 'value_codec.dart';

/// [CollectionCastValueCodec] for maps, which hive reads back as `Map<dynamic, dynamic>` whatever they
/// hold.
final class MapCastValueCodec<MK extends Object, MV extends Object>()
    implements ValueCodec<Map<MK, MV>> {
  /// Trips development asserts for an [MK] that might not compare equal after a restart, or an [MV]
  /// that won't read back typed.
  this
    : assert(
        isRestartSafeType<MK>(),
        'A map keyed by $MK may find nothing after a restart, which hands back fresh keys. Key '
        'it by a String, num, bool or enum instead, like an id.',
      ) {
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
