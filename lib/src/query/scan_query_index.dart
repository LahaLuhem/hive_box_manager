import '/src/codec/dual/dual_key_codec.dart';
import '/src/core/utils/no_op.dart';
import 'query_index_strategy.dart';

/// The 1.0 reverse-query strategy: a full decode-and-filter scan over the live key set.
///
/// O(K) per query, and free until you call one, which is why queries fold into the dual façades rather
/// than being their own family. It keeps no state of its own, hence the no-op hooks, and the keys arrive
/// through a closure so a scan always sees the current keystore.
// ignore: public_member_api_docs -- a primary constructor has nowhere to hang a doc comment.
final class ScanQueryIndex<K1 extends Object, K2 extends Object>({
  required final Iterable<Object> Function() _rawKeys,
  required final DualKeyCodec<K1, K2> _codec,
}) implements QueryIndexStrategy<K1, K2> {
  /// Nothing to maintain, queries decode the live key set instead.
  @override
  void afterWrite(Object rawKey, K1 primary, K2 secondary) => noop();

  /// Nothing to maintain, queries decode the live key set instead.
  @override
  void afterDelete(Object rawKey, K1 primary, K2 secondary) => noop();

  @override
  Iterable<Object> rawKeysByPrimary(K1 primary) =>
      _rawKeys().where((rawKey) => _codec.decode(rawKey).$1 == primary);

  @override
  Iterable<Object> rawKeysBySecondary(K2 secondary) =>
      _rawKeys().where((rawKey) => _codec.decode(rawKey).$2 == secondary);
}
