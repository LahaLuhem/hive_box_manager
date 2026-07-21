import '../key/key_codec.dart';
import 'dual_key_codec.dart';

/// Internal bridge that lets the keyed CRUD engines serve the dual façades unchanged: the
/// engine-facing key is the `(K1, K2)` record, and both directions delegate to the wrapped
/// [DualKeyCodec].
///
/// Never exported: consumers implement [DualKeyCodec]; the record plumbing is this package's
/// business. Keeping CRUD written once in the engines is the whole point of the adapter.
final class DualKeyCodecAdapter<K1 extends Object, K2 extends Object>
    implements KeyCodec<(K1, K2)> {
  final DualKeyCodec<K1, K2> _dualCodec;

  /// Wraps [_dualCodec] for engine consumption.
  const DualKeyCodecAdapter({required this._dualCodec});

  @override
  Object encode((K1, K2) key) => _dualCodec.encode(key.$1, key.$2);

  @override
  (K1, K2) decode(Object rawKey) => _dualCodec.decode(rawKey);
}
