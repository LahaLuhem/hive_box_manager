/// @docImport 'collection_cast_value_codec.dart';
library;

import 'dart:collection';

import 'package:meta/meta.dart';

import '/src/core/restart_safe.dart';
import 'element_type_check.dart';
import 'int_check.dart';
import 'value_codec.dart';

/// [CollectionCastValueCodec] for maps, which hive reads back as `Map<dynamic, dynamic>` whatever they
/// hold.
@internal
final class MapCastValueCodec<MK extends Object, MV extends Object>()
    implements ValueCodec<Map<MK, MV>> {
  /// Trips a development assert for an [MV] that won't read back typed.
  this {
    assertRestorableElementType<MV>();
  }

  final IntCheck? _intCheck = entriesCheckFor<MK, MV>();

  @override
  Object toStorable(Map<MK, MV> value) {
    assert(
      value.keys.every(isRestartSafeValue),
      '${value.keys.firstWhere((key) => !isRestartSafeValue(key)).runtimeType} keys compare by '
      'identity, so after a restart a lookup never finds them. Key the map by something with its '
      'own ==, like an id.',
    );
    _intCheck?.call(value);

    return value;
  }

  @override
  Map<MK, MV> fromStored(Object storedValue) {
    final storedMap = storedValue as Map<Object?, Object?>;
    // Written this session: nothing to check or cast. A map read from disk never comes back typed.
    if (storedMap is Map<MK, MV>) return UnmodifiableMapView(storedMap);

    checkEntryTypes<MK, MV>(storedMap);

    return UnmodifiableMapView(storedMap.cast<MK, MV>());
  }
}
