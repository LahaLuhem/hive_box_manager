import 'package:hive_box_manager/src/codec/dual/dual_key_codec.dart';

/// A consumer-shaped dual codec for part types with no default, driving the dual defaulting and
/// custom-codec paths in the façade suites. `|` separates the parts because ISO-8601 itself
/// contains `:`; bijective as the contract demands.
final class DateIntDualCodec implements DualKeyCodec<DateTime, int> {
  const new();

  /// Separates the ISO date from the int part inside the raw key.
  static const partSeparator = '|';

  @override
  Object encode(DateTime primary, int secondary) =>
      '${primary.toIso8601String()}$partSeparator$secondary';

  @override
  (DateTime, int) decode(Object rawKey) {
    final parts = (rawKey as String).split(partSeparator);

    return (DateTime.parse(parts.first), int.parse(parts.last));
  }
}
