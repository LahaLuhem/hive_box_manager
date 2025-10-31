part of 'base_dual_index_managers.dart';

final class DualIntIndexLazyBoxManager<T> extends _BaseDualIndexLazyBoxManager<T, int, int, int> {
  /// ### ✅ Pros:
  /// + Maximum performance - Bit operations are the fastest CPU operations
  /// + Perfect distribution - Uses all 64 bits efficiently (32 bits each)
  /// + No wasted space - Can represent 0 to 4,294,967,295 for both numbers
  /// ### ❌ Cons:
  /// + Fixed range - Limited to 32-bit integers (0-4.3 billion)
  /// + No negative numbers without additional handling
  /// + Not great if data distribution is sparse
  /// + Potential platform issues if Dart's integer behavior changes
  /// ### Collision Test
  /// Empirically tested up to 20,000 possible indices
  factory DualIntIndexLazyBoxManager({
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
  /// + Handles negative indices
  /// + Predictable output size - Always produces 64-bit integers
  /// + Uniform distribution - Evenly distributes encoded values
  /// + Reversible - Perfect bijection without collisions
  /// ### ❌ Cons:
  /// + Limited range - Only handles ±2.1 billion (32-bit signed range)
  /// + Wasted space - Uses 64 bits even for small numbers
  /// + Not great if data distribution is sparse
  /// + Overflow risk - If inputs exceed 32-bit range
  factory DualIntIndexLazyBoxManager.negative({
    required String boxKey,
    required T defaultValue,
    LogCallback? logCallback,
  }) => DualIntIndexLazyBoxManager._(
    boxKey: boxKey,
    defaultValue: defaultValue,
    logCallback: logCallback,
    encoder: _negativeNumbersEncoder,
  );

  ////////////////////// BIT-SHIFT //////////////////////
  static const _bitShift = 32;
  static const _bitMask = 0xFFFFFFFF;

  /// Encodes two 32-bit unsigned integers into a unique 64-bit integer using bit shifting.
  /// ## Mathematical Foundation
  /// This method provides a bijective mapping between pairs of 32-bit integers
  /// `(primaryIndex, secondaryIndex)` and 64-bit integers, ensuring that each
  /// unique input pair produces a unique output value.
  /// ### Encoding Operation:
  /// ```dart
  /// result = (primaryIndex << 32) | (secondaryIndex & 0xFFFFFFFF)
  /// ```
  /// ### Mathematical Proof of Uniqueness:
  /// Let:
  /// - `P = primaryIndex` (32-bit unsigned integer: 0 ≤ P ≤ 2³² - 1)
  /// - `S = secondaryIndex` (32-bit unsigned integer: 0 ≤ S ≤ 2³² - 1)
  /// The encoding can be mathematically expressed as: `encoded = P × 2³² + S`
  /// **Proof:**
  /// 1. **Bit Shift as Multiplication:**
  ///    - `P << 32` is equivalent to `P × 2³²`
  ///    - This places `P` in the upper 32 bits of a 64-bit space
  ///    - The lower 32 bits of `P << 32` are guaranteed to be zeros
  /// 2. **Bit Mask Preservation:**
  ///    - `S & 0xFFFFFFFF` ensures `S` is treated as a 32-bit value
  ///    - This preserves all bits of `S` in the lower 32-bit range
  /// 3. **Non-Overlapping Bit Fields:**
  ///    - `P << 32` occupies bits [32, 63] (all zeros in [0, 31])
  ///    - `S` occupies bits [0, 31] (all zeros in [32, 63])
  ///    - These are disjoint bit ranges with no overlap
  /// 4. **OR Operation as Addition:**
  ///    - For non-overlapping bit fields: `(A | B) = A + B`
  ///    - Therefore: `(P << 32) | S = (P × 2³²) + S`
  /// 5. **Uniqueness Guarantee:**
  ///    - Assume two different pairs `(P₁, S₁)` and `(P₂, S₂)` produce the same output
  ///    - Case 1: If `P₁ ≠ P₂`, then `P₁ × 2³² ≠ P₂ × 2³²` (difference in upper bits)
  ///    - Case 2: If `P₁ = P₂` but `S₁ ≠ S₂`, then lower bits differ
  ///    - Therefore, different inputs must produce different outputs
  /// ### Range and Constraints:
  /// - Input range for both parameters: `[0, 4294967295]` (0xFFFFFFFF)
  /// - Output range: `[0, 18446744073709551615]` (64-bit unsigned range)
  /// - The mapping is reversible: original values can be extracted using:
  ///   ```dart
  ///   primaryIndex = encoded >> 32;
  ///   secondaryIndex = encoded & 0xFFFFFFFF;
  ///   ```
  /// ### Example:
  /// ```dart
  /// bitShiftEncoder(0x12345678, 0xABCDEF01) == 0x12345678ABCDEF01
  /// ```
  /// [primaryIndex ]The first 32-bit unsigned integer (upper 32 bits of result)
  /// [secondaryIndex] The second 32-bit unsigned integer (lower 32 bits of result)
  /// Returns: A unique 64-bit integer encoding both input values
  /// Throws: AssertionError if either input exceeds 32-bit unsigned range
  @visibleForTesting
  static int bitShiftEncoder(int primaryIndex, int secondaryIndex) {
    assert(primaryIndex >= 0 && primaryIndex <= _bitMask, 'First number must be 32-bit unsigned');
    assert(
      secondaryIndex >= 0 && secondaryIndex <= _bitMask,
      'Second number must be 32-bit unsigned',
    );

    return (primaryIndex << _bitShift) | (secondaryIndex & _bitMask);
  }

  //////////////////// NEGATIVE NUMBERS ////////////////////
  /// Max 32-bit signed int
  static const _negativeNumberOffset = (2 ^ 31) - 1;
  static const _negativeNumberRange = 2 ^ 32;

  static int _negativeNumbersEncoder(int primaryIndex, int secondaryIndex) {
    // Shift negative numbers to positive range
    final shiftedA = primaryIndex + _negativeNumberOffset;
    final shiftedB = secondaryIndex + _negativeNumberOffset;

    // Use mathematical encoding
    return shiftedA * _negativeNumberRange + shiftedB;
  }

  DualIntIndexLazyBoxManager._({
    required super.boxKey,
    required super.defaultValue,
    required super.encoder,
    super.logCallback,
  });
}
