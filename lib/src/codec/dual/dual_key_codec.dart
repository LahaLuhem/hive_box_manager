/// @docImport '/src/codec/key/key_codec.dart';
/// @docImport 'packed_int_dual_codec.dart';
/// @docImport 'string_composite_dual_codec.dart';
library;

/// Encodes a two-part composite key into hive's raw key domain, and decodes it back.
///
/// Same raw-domain contract as a single-key codec, see [KeyCodec]. [decode] drives `keys` iteration,
/// typed watch events and both reverse-query directions, so the round-trip has to be exact.
///
/// 2 ship: [StringCompositeDualCodec], the safe default with no ceilings, and [PackedIntDualCodec],
/// the faster opt-in that caps each part at 16 bits. Implement this for other part types, and keep it
/// bijective or the reverse queries will lie to you.
abstract interface class DualKeyCodec<K1 extends Object, K2 extends Object> {
  /// Encodes the ([primary], [secondary]) pair into hive's raw key domain.
  Object encode(K1 primary, K2 secondary);

  /// Decodes a raw key previously produced by [encode] back into its 2 parts.
  (K1, K2) decode(Object rawKey);
}
