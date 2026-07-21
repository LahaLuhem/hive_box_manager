import 'dual_key_codec.dart';
import 'string_composite_dual_codec.dart';

/// Resolves the [DualKeyCodec] a dual façade wires for ([K1], [K2]): an [explicitCodec] always
/// wins, and `(int, int)` parts default to the safe [StringCompositeDualCodec].
///
/// Any other part pair without an explicit codec fails an assert at wiring time: construction
/// always runs in development and the check is data-independent, so the assert is the contract
/// (tier 1). The [ArgumentError] behind it is the honest release fallback, because a codec-less
/// box cannot function at all.
DualKeyCodec<K1, K2> resolveDualKeyCodec<K1 extends Object, K2 extends Object>(
  DualKeyCodec<K1, K2>? explicitCodec,
) {
  if (explicitCodec != null) return explicitCodec;

  assert(
    K1 == int && K2 == int,
    'No DualKeyCodec<$K1, $K2> given: only (int, int) parts default to the String-composite '
    'codec. Pass codec:.',
  );

  // Exact type equality first, then `is`-promotion without an `as` launder; see
  // resolveKeyCodec for why a bare `is` check would admit covariant supertype parts. The local
  // is typed Object so the `is` check narrows (promotion cannot widen a concrete static type).
  if (K1 == int && K2 == int) {
    const Object compositeDefault = StringCompositeDualCodec();
    if (compositeDefault is DualKeyCodec<K1, K2>) return compositeDefault;
  }

  throw ArgumentError.value('($K1, $K2)', 'codec', 'no DualKeyCodec given, and no default fits');
}
