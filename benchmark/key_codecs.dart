/// The composite-key packing candidates from the planning benchmarks (P1),
/// duplicated from `test/support/probe_codecs.dart` because the benchmark tree
/// cannot import test support cleanly; both copies are superseded by the real
/// `KeyCodec` implementations once Phase 1 lands them.
library;

/// Parts are 16-bit because Hive int keys are unsigned 32-bit.
const int partCeiling = 1 << 16;

/// Mask selecting one 16-bit part.
const partMask = 0xFFFF;

/// Arithmetic packing: no bitwise ops, so exact under JS number semantics.
int arithPack(int primary, int secondary) => primary * partCeiling + secondary;

/// Inverse of [arithPack].
(int, int) arithUnpack(int key) => (key ~/ partCeiling, key % partCeiling);

/// The 0.0.x bit-shift packing, kept as the byte-compatibility reference lane.
int bitShiftPack(int primary, int secondary) => (primary << 16) | secondary;

/// Inverse of [bitShiftPack].
(int, int) bitShiftUnpack(int key) => (key >> 16, key & partMask);

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
