import 'int_key_codec.dart';
import 'key_codec.dart';
import 'string_key_codec.dart';

/// Resolves the [KeyCodec] a keyed façade wires for [K]: an [explicitCodec] always wins, and
/// `int` / `String` keys default to the identity codecs.
///
/// Any other [K] without an explicit codec fails an assert at wiring time: construction always
/// runs in development and the check is data-independent, so the assert is the contract
/// (tier 1). The [ArgumentError] behind it is the honest release fallback, because a codec-less
/// box cannot function at all.
KeyCodec<K> resolveKeyCodec<K extends Object>(KeyCodec<K>? explicitCodec) {
  if (explicitCodec != null) return explicitCodec;

  // Only the type parameter exists to inspect (there is no value to pattern-match), so pick the
  // int identity for int keys and fall through to the String identity for everything else: the
  // `is` check below promotes the fit (no `as` launder) and rejects every non-String misfit.
  final identityCodec = K == int ? const IntKeyCodec() : const StringKeyCodec();
  assert(
    identityCodec is KeyCodec<K>,
    'No KeyCodec<$K> given: only int and String keys default to identity codecs. Pass codec:.',
  );
  if (identityCodec is KeyCodec<K>) return identityCodec;

  throw ArgumentError.value(K, 'codec', 'no KeyCodec given, and $K has no identity default');
}
