/// Test-side companion to the library's key limits: re-exports `HiveKeyLimits` (one home, so the
/// pins and the gate cannot drift apart) and adds the probe-only sampling values that are not
/// engine limits.
library;

export 'package:hive_box_manager/src/core/constants/hive_key_limits.dart';

/// Sampling values used only by the behaviour probes, beyond the real engine limits.
abstract final class ProbeKeyLimits {
  /// The first integer a JS double cannot represent exactly (2^53 + 1). hive_ce warns above
  /// 2^53, and the key pins show it wraps into u32 like any other out-of-range int. An
  /// expression because a literal this large would trip `avoid_js_rounded_ints`; only VM code
  /// consumes it.
  static const firstWebImpreciseInt = (1 << 53) + 1;

  /// An arbitrary far-beyond-the-limit String-key length: the second corruption sample, showing
  /// the failure is not specific to the exact boundary.
  static const farOversizedKeyLength = 300;
}
