import 'key_codec.dart';

/// Identity codec for boxes keyed by raw hive `int` keys (`0..0xFFFFFFFF`).
///
/// Purely pass-through: domain enforcement lives in the write-path gate, which fails loudly at
/// the call site where release-mode hive_ce would silently wrap the key and corrupt the write.
final class IntKeyCodec implements KeyCodec<int> {
  /// Const so façades can default to it without an allocation per box.
  const IntKeyCodec();

  @override
  Object encode(int key) => key;

  @override
  int decode(Object rawKey) => rawKey as int;
}
