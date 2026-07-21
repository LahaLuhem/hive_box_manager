import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:listenable_collections/listenable_collections.dart';

/// Streams every semantic box event into a live list the log panel renders: the package's
/// observer seam, pointed at the UI instead of a logger. Newest entry first.
final class LogPanelObserver extends BoxObserver {
  final entries = ListNotifier<String>();

  void clearEntries() => entries.clear();

  @override
  void onOpened(String boxName) => _log('opened [$boxName]');

  @override
  void onClosed(String boxName) => _log('closed [$boxName]');

  @override
  void onDeletedFromDisk(String boxName) => _log('deleted [$boxName] from disk');

  @override
  void onCleared(String boxName) => _log('cleared [$boxName]');

  @override
  void onRead(String boxName, Object key, Object? value) => _log('read [$boxName] $key -> $value');

  @override
  void onReadAll(String boxName, int valueCount) => _log('read all [$boxName]: $valueCount values');

  @override
  void onWritten(String boxName, Object key, Object value) =>
      _log('wrote [$boxName] $key = $value');

  @override
  void onWrittenAll(String boxName, int entryCount) =>
      _log('wrote $entryCount entries to [$boxName]');

  @override
  void onDeleted(String boxName, Object key) => _log('deleted [$boxName] $key');

  @override
  void onOperationError(String boxName, String operation, Object error, StackTrace stackTrace) =>
      _log('ERROR in $operation on [$boxName]: $error');

  void _log(String line) => entries.insert(0, line);
}
