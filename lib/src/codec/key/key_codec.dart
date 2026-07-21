/// @docImport 'int_key_codec.dart';
/// @docImport 'string_key_codec.dart';
library;

/// Encodes consumer-facing keys of type [K] into hive's raw key domain, and decodes them back.
///
/// The raw domain is hive's, not ours: [encode] must produce an `int` within `0..0xFFFFFFFF`
/// (u32) or a `String` of at most 255 UTF-8 bytes. The write path enforces that contract with a
/// release-mode gate (an [ArgumentError] at the call site), because release-mode hive_ce
/// silently corrupts on violations instead of throwing.
///
/// [decode] is load-bearing beyond plain reads: `keys` iteration, typed watch events, and the
/// dual-key reverse query all decode raw keys back into [K]. The two functions live on one
/// interface deliberately: the 0.0.x paired-function seam let encode and decode drift apart and
/// shipped a real bug.
///
/// Implement this to key boxes by any type; the shipped [IntKeyCodec] and [StringKeyCodec] are
/// the identity codecs the keyed façades default to for `int` / `String` keys.
abstract interface class KeyCodec<K extends Object> {
  /// Encodes [key] into hive's raw key domain: an `int` in u32, or a `String` of at most 255
  /// UTF-8 bytes.
  Object encode(K key);

  /// Decodes a raw key previously produced by [encode] back into [K].
  K decode(Object rawKey);
}
