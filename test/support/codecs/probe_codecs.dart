/// The composite-key packing candidates from the planning benchmarks (P1 / P2), as plain functions:
/// the Phase 0 pins assert *platform* arithmetic (JS and wasm number semantics), not library code.
/// Superseded by the real `KeyCodec` implementations once Phase 1 lands them.
library;

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
  final parts = key.split(':');

  return (int.parse(parts.first), int.parse(parts.last));
}
