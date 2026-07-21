/// @docImport 'scan_query_index.dart';
library;

/// Internal seam behind the dual façades' reverse query, shaped so the 1.x inverted-index multi-box
/// strategy plugs in without touching the public surface (the ratified paper-fit proof): every write
/// and delete flows through the hooks with both the raw key and the decoded parts, which is all an
/// index needs to maintain side state.
///
/// 1.0 ships only [ScanQueryIndex]; the interface stays internal until a second implementation earns
/// making it public. `clear()` deliberately has no hook yet: the scan needs none, and being
/// internal, the seam gains one for free when the 1.x index arrives. Hooks fire per requested
/// key (an absent-key delete still dispatches; hive no-ops it and so does the scan).
abstract interface class QueryIndexStrategy<K1 extends Object, K2 extends Object> {
  /// Observes one written raw key with its decoded parts (index maintenance hook).
  void afterWrite(Object rawKey, K1 primary, K2 secondary);

  /// Observes one deleted raw key with its decoded parts (index maintenance hook).
  void afterDelete(Object rawKey, K1 primary, K2 secondary);

  /// Raw keys whose primary part equals [primary].
  Iterable<Object> rawKeysByPrimary(K1 primary);

  /// Raw keys whose secondary part equals [secondary].
  Iterable<Object> rawKeysBySecondary(K2 secondary);
}
