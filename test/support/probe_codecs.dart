/// The composite-key packing candidates from the planning benchmarks (P1 / P2), as plain functions:
/// the Phase 0 pins assert *platform* arithmetic (JS and wasm number semantics), not library code.
/// Superseded by the real `KeyCodec` implementations once Phase 1 lands them.
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
  final parts = key.split(':');

  return (int.parse(parts.first), int.parse(parts.last));
}
