import 'package:hive_ce/hive.dart';
// hive_ce defaults to these 2 but never exports them, so the only way to pass them through is the
// implementation path.
// ignore: implementation_imports
import 'package:hive_ce/src/box/default_compaction_strategy.dart';
// ignore: implementation_imports -- same oversight as above.
import 'package:hive_ce/src/box/default_key_comparator.dart';

/// Internal lifecycle core: the one place boxes are acquired.
///
/// Wraps the global [Hive] and takes an injected one for tests. Boxes open as `Object?`, since the engines'
/// value codecs do the typing at the read and write boundary, and hive won't open a typed collection
/// box anyway.
///
/// Cipher, key comparator, compaction strategy and crash recovery all go straight through, and so does
/// whatever `openBox` throws.
final class BoxProvider {
  final HiveInterface _hive;

  /// Wires the provider to [hive], defaulting to the global instance.
  new({HiveInterface? hive}) : _hive = hive ?? Hive;

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
