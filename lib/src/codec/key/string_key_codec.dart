import 'key_codec.dart';

/// Identity codec for boxes already keyed by hive `String` keys. Non-ASCII is fine, just remember the
/// limit counts bytes, not characters.
///
/// Purely pass-through: length enforcement lives in the write-path gate, which fails loudly at the call
/// site where release-mode hive_ce would accept the key and corrupt the whole box file.
final class StringKeyCodec implements KeyCodec<String> {
  /// Const so façades can default to it without an allocation per box.
  const new();

  @override
  Object encode(String key) => key;

  @override
  String decode(Object rawKey) => rawKey as String;
}
