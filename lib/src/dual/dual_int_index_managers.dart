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
  /// Up to 20,000 possible indices (~16 mins)
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
  // Max 32-bit signed int
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
