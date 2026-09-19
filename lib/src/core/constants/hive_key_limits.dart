/// The limits hive_ce's raw keys have to stay inside. Release mode enforces neither itself, which is
/// why `ensureStorableRawKey` exists.
abstract final class HiveKeyLimits {
  /// The biggest int key hive will store. They are unsigned 32-bit.
  static const maxIntKey = 0xFFFFFFFF;

  /// How long a String key may be in UTF-8 bytes. One byte more corrupts the box file in release mode.
  static const maxStringKeyBytes = 255;
}
