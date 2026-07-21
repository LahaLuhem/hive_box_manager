/// @docImport 'packed_int_dual_codec.dart';
library;

import 'dual_key_codec.dart';

/// The default dual-key codec: packs two `int` parts into a compact decimal
/// `'$primary:$secondary'` String key.
///
/// Safe by default: parts span the platform's full int range (i64 on the VM; web ints are
/// doubles, exact to 2^53), negatives included, and the worst case costs 41 of hive's 255 key
/// bytes, so nothing can overflow or corrupt. Deliberately not zero-padded: padding would buy
/// lexicographic sortability but roughly doubles key bytes, and memory is the String scheme's
/// weak axis. Reach for [PackedIntDualCodec] instead when the measured eager-path / memory wins
/// matter and both parts fit 16 bits.
final class StringCompositeDualCodec implements DualKeyCodec<int, int> {
  /// Const so façades can default to it without an allocation per box.
  const StringCompositeDualCodec();

  /// Separates the two decimal parts inside the raw key.
  static const partSeparator = ':';

  @override
  Object encode(int primary, int secondary) => '$primary$partSeparator$secondary';

  @override
  (int, int) decode(Object rawKey) {
    final parts = (rawKey as String).split(partSeparator);

    return (int.parse(parts.first), int.parse(parts.last));
  }
}
