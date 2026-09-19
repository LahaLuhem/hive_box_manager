/// @docImport 'string_composite_dual_codec.dart';
library;

import 'dual_key_codec.dart';

/// The opt-in performance dual-key codec: packs 2 parts of 16 bits arithmetically into one u32 `int` key.
///
/// Byte-identical to the 0.0.x `.bitShift` scheme for in-range parts, so those boxes still read. It
/// wins on eager gets, open time, keystore memory, file size and key scans (`benchmark/key_codecs.dart`),
/// while lazy reads and single writes don't care either way because disk dominates. The price is the
/// ceiling: both parts have to fit 16 bits.
///
/// Part domains are asserted in development and left unchecked in release, which is the whole point
/// of this codec. An out-of-domain part is a fix-your-data problem, and the write-path gate still catches
/// any packed result that escapes hive's raw domain. Arithmetic rather than bitwise, because the values
/// are identical and arithmetic stays exact under JS number semantics.
final class PackedIntDualCodec implements DualKeyCodec<int, int> {
  /// Const so façades can default to it without an allocation per box.
  const new();

  /// Each part gets half of a u32 hive int key.
  static const bitsPerPart = 16;

  /// Exclusive ceiling of one packed part.
  static const partCeiling = 1 << bitsPerPart;

  /// Largest value one part can hold.
  static const maxPart = partCeiling - 1;

  @override
  Object encode(int primary, int secondary) {
    assert(
      primary >= 0 && primary <= maxPart,
      'primary part must be within 0..$maxPart, got $primary',
    );
    assert(
      secondary >= 0 && secondary <= maxPart,
      'secondary part must be within 0..$maxPart, got $secondary',
    );

    return primary * partCeiling + secondary;
  }

  @override
  (int, int) decode(Object rawKey) {
    final packedKey = rawKey as int;

    return (packedKey ~/ partCeiling, packedKey % partCeiling);
  }
}
