/// Test-side companion to the library's hive key limits: re-exports the graduated limits (one
/// home, so the pins and the gate cannot drift apart) and keeps the probe-only sampling
/// parameters that are not engine limits.
library;

export 'package:hive_box_manager/src/core/hive_key_limits.dart';

/// The first integer a JS double cannot represent exactly (2^53 + 1). hive_ce warns above 2^53,
/// and the key pins show it wraps into u32 like any other out-of-range int. Written as an
/// expression because a literal this large would trip `avoid_js_rounded_ints`; only VM code
/// consumes it.
const int firstWebImpreciseInt = (1 << 53) + 1;

/// An arbitrary far-beyond-the-limit String-key length: the second corruption sample, showing
/// the failure is not specific to the exact boundary.
const farOversizedKeyLength = 300;
