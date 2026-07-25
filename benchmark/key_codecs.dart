/// The composite-key packing candidates from the planning benchmarks (P1),
/// duplicated from `test/support/probe_codecs.dart` because the benchmark tree
/// cannot import test support cleanly.
///
/// These are the matrix lane's **raw baseline**, not dead code: `bench.dart`'s `raw` impl packs
/// with these hand-inlined functions while its `facade` impl goes through the shipped
/// `DualKeyCodec`s, and the pair is what turns the lane into a wrapper-overhead measurement.
/// They also carry the `bitshift` reference scheme, which no shipped codec implements.
///
/// Keep them byte-compatible with the shipped codecs ([arithPack] with `PackedIntDualCodec`,
/// [stringPack] with `StringCompositeDualCodec`): the driver preps one box file per
/// (keyKind, scale) and points both impls at it, so a divergence here silently stops comparing
/// like with like.
library;

// Decode sits inside measured lanes (micro + scan): `substring` keeps the implementation
// identical to what the preserved results/ data measured, and the key domain is ASCII decimal
// digits + ':', so the rule's UTF-16 concern is void.
// ignore_for_file: avoid-substring

/// Each packed part gets half a hive int key: hive int keys are unsigned 32-bit.
const bitsPerPart = 16;

/// Exclusive ceiling of one packed part.
const int partCeiling = 1 << bitsPerPart;

/// Mask selecting one packed part.
const partMask = partCeiling - 1;

/// Arithmetic packing: no bitwise ops, so exact under JS number semantics.
int arithPack(int primary, int secondary) => primary * partCeiling + secondary;

/// Inverse of [arithPack].
(int, int) arithUnpack(int key) => (key ~/ partCeiling, key % partCeiling);

/// The 0.0.x bit-shift packing, kept as the byte-compatibility reference lane.
int bitShiftPack(int primary, int secondary) => (primary << bitsPerPart) | secondary;

/// Inverse of [bitShiftPack].
(int, int) bitShiftUnpack(int key) => (key >> bitsPerPart, key & partMask);

/// String composite packing (the 1.0 safe default's scheme).
String stringPack(int primary, int secondary) => '$primary:$secondary';

/// Inverse of [stringPack].
(int, int) stringUnpack(String key) {
  final separatorIndex = key.indexOf(':');

  return (
    int.parse(key.substring(0, separatorIndex)),
    int.parse(key.substring(separatorIndex + 1)),
  );
}
