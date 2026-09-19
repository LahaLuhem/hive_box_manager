/// @docImport 'packed_int_dual_codec.dart';
library;

import 'dual_key_codec.dart';

/// The default dual-key codec: packs 2 `int` parts into a compact decimal `'$primary:$secondary'`
/// String key.
///
/// Safe by default: parts cover the platform's whole int range, negatives included, and even the worst
/// case fits comfortably inside hive's key budget. Not zero-padded on purpose, since padding would buy
/// lexicographic sorting and roughly double the key bytes, and memory is this scheme's weak spot. Reach
/// for [PackedIntDualCodec] when both parts fit 16 bits and the speed is worth it.
final class StringCompositeDualCodec implements DualKeyCodec<int, int> {
  /// Const so façades can default to it without an allocation per box.
  const new();

  /// Separates the 2 decimal parts inside the raw key.
  static const partSeparator = ':';

  @override
  Object encode(int primary, int secondary) => '$primary$partSeparator$secondary';

  @override
  (int, int) decode(Object rawKey) {
    final parts = (rawKey as String).split(partSeparator);

    return (int.parse(parts.first), int.parse(parts.last));
  }
}
