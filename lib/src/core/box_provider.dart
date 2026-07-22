import 'package:hive_ce/hive.dart';
// hive_ce's public openBox/openLazyBox signatures *default* to these two symbols but the barrel
// never exports them, so passing them through needs the implementation paths (upstream
// packaging oversight). The caret-open dependency plus compile visibility keeps any upstream
// move loud.
// ignore: implementation_imports
import 'package:hive_ce/src/box/default_compaction_strategy.dart';
// ignore: implementation_imports -- same oversight as above.
import 'package:hive_ce/src/box/default_key_comparator.dart';

/// Internal lifecycle core: the one place boxes are acquired.
///
/// Wraps the global [Hive] by default and is injectable for tests; at 1.x this is also the seam
/// where an IsolatedHive-backed provider plugs in (lazy-only, since isolated boxes are all-async).
/// Boxes open `Object?`-parameterised: the engines' value codecs own typing at the read/write boundary,
/// and collections could not open typed anyway (hive refuses or traps on typed collection boxes; pinned).
///
/// hive_ce's own pluggables pass through untouched: cipher, key comparator, compaction strategy,
/// crash recovery. No wrapper preconditions here: whatever `openBox` throws for (wrong-kind reopen, unknown types)
/// surfaces as the engine's own error (tier 3).
final class BoxProvider {
  final HiveInterface _hive;

  /// Wires the provider to [hive], defaulting to the global instance.
  BoxProvider({HiveInterface? hive}) : _hive = hive ?? Hive;

  /// Opens (or returns the already-open instance of) the eager box named [name].
  Future<Box<Object?>> openEagerBox(
    String name, {
    HiveCipher? cipher,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) => _hive.openBox<Object?>(
    name,
    encryptionCipher: cipher,
    keyComparator: keyComparator ?? defaultKeyComparator,
    compactionStrategy: compactionStrategy ?? defaultCompactionStrategy,
    crashRecovery: crashRecovery,
  );

  /// Opens (or returns the already-open instance of) the lazy box named [name].
  Future<LazyBox<Object?>> openLazyBox(
    String name, {
    HiveCipher? cipher,
    KeyComparator? keyComparator,
    CompactionStrategy? compactionStrategy,
    bool crashRecovery = true,
  }) => _hive.openLazyBox<Object?>(
    name,
    encryptionCipher: cipher,
    keyComparator: keyComparator ?? defaultKeyComparator,
    compactionStrategy: compactionStrategy ?? defaultCompactionStrategy,
    crashRecovery: crashRecovery,
  );
}
