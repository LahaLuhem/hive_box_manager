import 'dual_key_codec.dart';
import 'string_composite_dual_codec.dart';

/// Resolves the [DualKeyCodec] a dual façade wires for ([K1], [K2]): an [explicitCodec] always wins,
/// and `(int, int)` parts default to the safe [StringCompositeDualCodec].
///
/// Any other part pair without a codec trips an assert while wiring. Construction always runs in development
/// and the check doesn't depend on data, so the assert is the real contract. The [ArgumentError] behind
/// it is the release fallback, since a codec-less box can't work at all.
DualKeyCodec<K1, K2> resolveDualKeyCodec<K1 extends Object, K2 extends Object>(
  DualKeyCodec<K1, K2>? explicitCodec,
) {
  if (explicitCodec != null) return explicitCodec;

  assert(
    K1 == int && K2 == int,
    'No DualKeyCodec<$K1, $K2> given: only (int, int) parts default to the String-composite '
    'codec. Pass codec:.',
  );

  // Exact type equality first, then `is`-promotion, see resolveKeyCodec for why. The local is typed
  // `Object` so the check narrows, since promotion can't widen a concrete static type.
  if (K1 == int && K2 == int) {
    const Object compositeDefault = StringCompositeDualCodec();
    if (compositeDefault is DualKeyCodec<K1, K2>) return compositeDefault;
  }

  throw ArgumentError.value('($K1, $K2)', 'codec', 'no DualKeyCodec given, and no default fits');
}
