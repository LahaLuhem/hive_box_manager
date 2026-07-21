/// @docImport 'packed_int_dual_codec.dart';
/// @docImport 'string_composite_dual_codec.dart';
library;

/// Encodes a two-part composite key into hive's raw key domain, and decodes it back.
///
/// Same raw-domain contract as a single-key codec: [encode] must produce an `int` within
/// `0..0xFFFFFFFF` (u32) or a `String` of at most 255 UTF-8 bytes; the write path gates that in
/// release mode because hive_ce corrupts silently there. [decode] powers `keys` iteration,
/// typed watch events, and both reverse-query directions, so the round-trip must be exact.
///
/// Two implementations ship: [StringCompositeDualCodec] (the safe default: full-range parts, no
/// ceilings) and [PackedIntDualCodec] (the measured perf opt-in with a 16-bit-per-part ceiling).
/// Implement this interface for other part types; keep the separator or packing discipline bijective,
/// or reverse queries will lie.
abstract interface class DualKeyCodec<K1 extends Object, K2 extends Object> {
  /// Encodes the ([primary], [secondary]) pair into hive's raw key domain.
  Object encode(K1 primary, K2 secondary);

  /// Decodes a raw key previously produced by [encode] back into its two parts.
  (K1, K2) decode(Object rawKey);
}
