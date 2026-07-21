/// hive_ce's raw-key domain limits, as pinned by the key-constraint suite. These graduate into
/// the library alongside the Phase 1 corruption gate; until then this file is their one home so
/// the pins and the release-mode probe cannot drift apart.
library;

/// Int keys are unsigned 32-bit; this is the largest storable int key (how hive's own error
/// message frames it: "range 0 - 0xFFFFFFFF").
const hiveMaxIntKey = 0xFFFFFFFF;

/// String keys are capped at this many UTF-8 bytes; one byte more corrupts the whole box file in
/// release mode (see the key-constraint pins).
const hiveMaxStringKeyBytes = 255;

/// The first integer a JS double cannot represent exactly (2^53 + 1). hive_ce warns above 2^53,
/// and the key pins show it wraps into u32 like any other out-of-range int. Written as an
/// expression because a literal this large would trip `avoid_js_rounded_ints`; only VM code
/// consumes it.
const int firstWebImpreciseInt = (1 << 53) + 1;

/// An arbitrary far-beyond-the-limit String-key length: the second corruption sample, showing the
/// failure isn't specific to the exact boundary.
const farOversizedKeyLength = 300;
