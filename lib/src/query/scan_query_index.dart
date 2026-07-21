// The maintenance hooks are deliberate no-ops (scan keeps no side state); DCM's TODO-or-code
// rule doesn't fit a contract-mandated empty body.
// ignore_for_file: no-empty-block
import '../codec/dual_key_codec.dart';
import 'query_index_strategy.dart';

/// The 1.0 reverse-query strategy: a full decode-and-filter scan over the live key set.
///
/// O(K) per query and honestly documented as such; free until called, which is why the query
/// surface folds into the dual façades instead of being its own family. Maintains no side
/// state, so its hooks are deliberate no-ops. The keys come through a closure so the strategy
/// always scans the box's *current* keystore.
final class ScanQueryIndex<K1 extends Object, K2 extends Object>
    implements QueryIndexStrategy<K1, K2> {
  /// Wires the scan over [rawKeys] (the live key set) decoded by [codec].
  ScanQueryIndex({
    required Iterable<Object> Function() rawKeys,
    required DualKeyCodec<K1, K2> codec,
  }) : _rawKeys = rawKeys,
       _codec = codec;

  final Iterable<Object> Function() _rawKeys;
  final DualKeyCodec<K1, K2> _codec;

  @override
  void afterWrite(Object rawKey, K1 primary, K2 secondary) {
    // Scan maintains no side state; queries decode the live key set instead.
  }

  @override
  void afterDelete(Object rawKey, K1 primary, K2 secondary) {
    // Scan maintains no side state; queries decode the live key set instead.
  }

  @override
  Iterable<Object> rawKeysByPrimary(K1 primary) =>
      _rawKeys().where((rawKey) => _codec.decode(rawKey).$1 == primary);

  @override
  Iterable<Object> rawKeysBySecondary(K2 secondary) =>
      _rawKeys().where((rawKey) => _codec.decode(rawKey).$2 == secondary);
}
