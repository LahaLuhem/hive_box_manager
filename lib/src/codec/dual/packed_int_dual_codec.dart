/// @docImport 'string_composite_dual_codec.dart';
library;

import 'dual_key_codec.dart';

/// The opt-in performance dual-key codec: packs two 16-bit parts arithmetically into one u32
/// `int` key.
///
/// Byte-identical to the 0.0.x `.bitShift` scheme for in-range parts (`(p << 16) | s` equals
/// `p * 2^16 + s` there), so 0.0.x bit-shift boxes read in place. The measured wins over the
/// String default live on eager gets, box open time, keystore memory, file size, and key scans;
/// lazy reads and single-key writes are codec-indifferent because disk dominates. The price is
/// the domain ceiling: both parts must fit `0..65535`.
///
/// Part domains are asserted in development and deliberately unchecked in release (the
/// zero-cost path this codec exists for): an out-of-domain part is a fix-your-data error, and
/// the write-path gate still rejects any packed result that escapes the u32 raw domain.
/// Arithmetic rather than bitwise on principle: identical values, and exact under JS number
/// semantics without leaning on web bitwise guarantees.
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
