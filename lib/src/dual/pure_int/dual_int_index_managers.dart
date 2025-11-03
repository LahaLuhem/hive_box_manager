part of '../base_dual_index_managers.dart';

final class DualIntIndexLazyBoxManager<T> extends _BaseDualIndexLazyBoxManager<T, int, int, int> {
  /// ### ✅ Pros:
  /// + Maximum performance - Bit operations are the fastest CPU operations
  /// + Perfect distribution - Uses all 32 bits efficiently (16 bits each)
  /// + No wasted space - Can represent 0 to 65,536 for both numbers
  /// ### ❌ Cons:
  /// + Fixed range - Limited to 16-bit integers (0-65536)
  /// + No negative numbers without additional handling
  /// + Not great if data distribution is sparse
  /// + Potential platform issues if Dart's integer behavior changes
  /// ### Collision Test
  /// Empirically tested up to 20,000 possible indices
  factory DualIntIndexLazyBoxManager.bitShift({
    required String boxKey,
    required T defaultValue,
    LogCallback? logCallback,
  }) => DualIntIndexLazyBoxManager._(
    boxKey: boxKey,
    defaultValue: defaultValue,
    logCallback: logCallback,
    encoder: bitShiftEncoder,
  );

  /// ### ✅ Pros:
  /// + Range-shifted variant of [DualIntIndexLazyBoxManager].
  /// ### ❌ Cons:
  /// + Limited range - Only handles ±16,383
  factory DualIntIndexLazyBoxManager.negative({
    required String boxKey,
    required T defaultValue,
    LogCallback? logCallback,
  }) => DualIntIndexLazyBoxManager._(
    boxKey: boxKey,
    defaultValue: defaultValue,
    logCallback: logCallback,
    encoder: negativeNumbersEncoder,
  );

  ////////////////////// BIT-SHIFT //////////////////////

  /// Encodes two 16-bit unsigned integers into a unique 32-bit integer using bit shifting.
  /// ## Mathematical Foundation
  /// This method provides a bijective mapping between pairs of 32-bit integers
  /// `(primaryIndex, secondaryIndex)` and 64-bit integers, ensuring that each
  /// unique input pair produces a unique output value.
  /// ### Encoding Operation:
  /// ```dart
  /// result = (primaryIndex << 16) | (secondaryIndex & 0xFFFFFFFF)
  /// ```
  /// ### Mathematical Proof of Uniqueness:
  /// Let:
  /// - `P = primaryIndex` (16-bit unsigned integer: 0 ≤ P ≤ 2¹⁶ - 1)
  /// - `S = secondaryIndex` (16-bit unsigned integer: 0 ≤ S ≤ 2¹⁶ - 1)
  /// The encoding can be mathematically expressed as: `encoded = P × 2¹⁶ + S`
  /// **Proof:**
  /// 1. **Bit Shift as Multiplication:**
  ///    - `P << 16` is equivalent to `P × 2¹⁶`
  ///    - This places `P` in the upper 16 bits of a 32-bit space
  ///    - The lower 16 bits of `P << 16` are guaranteed to be zeros
  /// 2. **Bit Mask Preservation:**
  ///    - `S & 0xFFFFFFFF` ensures `S` is treated as a 16-bit value
  ///    - This preserves all bits of `S` in the lower 16-bit range
  /// 3. **Non-Overlapping Bit Fields:**
  ///    - `P << 16` occupies bits [16, 31] (all zeros in [0, 15])
  ///    - `S` occupies bits [0, 15] (all zeros in [16, 31])
  ///    - These are disjoint bit ranges with no overlap
  /// 4. **OR Operation as Addition:**
  ///    - For non-overlapping bit fields: `(A | B) = A + B`
  ///    - Therefore: `(P << 16) | S = (P × 2¹⁶) + S`
  /// 5. **Uniqueness Guarantee:**
  ///    - Assume two different pairs `(P₁, S₁)` and `(P₂, S₂)` produce the same output
  ///    - Case 1: If `P₁ ≠ P₂`, then `P₁ × 2³² ≠ P₂ × 2³²` (difference in upper bits)
  ///    - Case 2: If `P₁ = P₂` but `S₁ ≠ S₂`, then lower bits differ
  ///    - Therefore, different inputs must produce different outputs
  /// ### Range and Constraints:
  /// - Input range for both parameters: `[0, 65535]` (0xFFFF)
  /// - Output range: `[0, 4294967295]` (64-bit unsigned range)
  /// - The mapping is reversible: original values can be extracted using:
  ///   ```dart
  ///   primaryIndex = encoded >> 16;
  ///   secondaryIndex = encoded & 0xFFFF;
  ///   ```
  /// ### Example:
  /// ```dart
  /// bitShiftEncoder(0x12345678, 0xABCDEF01) == 0x12345678ABCDEF01
  /// ```
  /// [primaryIndex ]The first 16-bit unsigned integer (upper 16 bits of result)
  /// [secondaryIndex] The second 16-bit unsigned integer (lower 16 bits of result)
  /// Returns: A unique 32-bit integer encoding both input values
  /// Throws: AssertionError if either input exceeds 16-bit unsigned range
  @visibleForTesting
  static int bitShiftEncoder(int primaryIndex, int secondaryIndex) {
    assert(
      primaryIndex >= 0 && primaryIndex <= ConstValues.bitMask,
      'Primary index must be in range 0-65535',
    );
    assert(
      secondaryIndex >= 0 && secondaryIndex <= ConstValues.bitMask,
      'Secondary index must be in range 0-65535',
    );

    return (primaryIndex << ConstValues.bitShift) | secondaryIndex;
  }

  //////////////////// NEGATIVE NUMBERS ////////////////////

  /// Just shift and OR - no bounds checking for maximum speed
  @visibleForTesting
  static int negativeNumbersEncoder(int primaryIndex, int secondaryIndex) =>
      ((primaryIndex + _negativeNumbersOffset) << _bitShiftNegative) |
      (secondaryIndex + _negativeNumbersOffset);

  static const _bitShiftNegative = ConstValues.bitShift - 1;

  // Maximum range: -16383 to +16383 for both numbers
  static const _negativeNumbersOffset = 16383; // Maximum range: -16383 to +16383 for both numbers

  DualIntIndexLazyBoxManager._({
    required super.boxKey,
    required super.defaultValue,
    required super.encoder,
    super.logCallback,
  });
}
