/// @docImport 'int_key_codec.dart';
/// @docImport 'string_key_codec.dart';
library;

/// Encodes consumer-facing keys of type [K] into hive's raw key domain, and decodes them back.
///
/// The raw domain is hive's, not ours, so [encode] has to land on an `int` or `String` inside hive's
/// limits. The write path checks that even in release, because hive_ce quietly corrupts there instead
/// of throwing.
///
/// [decode] does more than plain reads: `keys` iteration, typed watch events and the reverse queries
/// all go through it. Both halves share one interface on purpose, because the 0.0.x paired-function
/// version let them drift apart and shipped a bug.
///
/// Implement this to key boxes by any type. [IntKeyCodec] and [StringKeyCodec] ship as the identity
/// codecs the keyed façades fall back on.
abstract interface class KeyCodec<K extends Object> {
  /// Encodes [key] into hive's raw key domain: an `int` in u32, or a `String` of at most 255 UTF-8 bytes.
  Object encode(K key);

  /// Decodes a raw key previously produced by [encode] back into [K].
  K decode(Object rawKey);
}
