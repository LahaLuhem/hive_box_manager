/// @docImport 'scan_query_index.dart';
library;

/// Internal seam behind the dual façades' reverse query, shaped so a real inverted index can replace
/// the scan later without touching the public surface. Writes and deletes flow through the hooks with
/// the raw key and the decoded parts, which is everything an index needs.
///
/// [ScanQueryIndex] is the only implementation so far, so this stays internal until a second one earns
/// making it public. `clear()` has no hook because the scan doesn't need one. Hooks fire per key asked
/// for, even a delete of a key that isn't there.
abstract interface class QueryIndexStrategy<K1 extends Object, K2 extends Object> {
  /// One written raw key with its decoded parts, for an index to record.
  void afterWrite(Object rawKey, K1 primary, K2 secondary);

  /// One deleted raw key with its decoded parts, for an index to record.
  void afterDelete(Object rawKey, K1 primary, K2 secondary);

  /// Raw keys whose primary part equals [primary].
  Iterable<Object> rawKeysByPrimary(K1 primary);

  /// Raw keys whose secondary part equals [secondary].
  Iterable<Object> rawKeysBySecondary(K2 secondary);
}
