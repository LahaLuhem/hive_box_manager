// coverage:ignore-file -- smoke-only sink, excluded from the coverage ratio per sibling
// precedent: every method is a one-line forward to dart:developer.
import 'dart:developer' as developer;

import '../box_observer.dart';

/// Ready-made sink forwarding every box event to `dart:developer`'s log under a configurable logger
/// [name], so DevTools can filter the package's diagnostics as one channel.
///
/// Pure-Dart-safe (`debugPrint` is Flutter-only), `avoid_print`-compliant, and dependency-free.
/// Errors log at level 900 (SEVERE on `package:logging`'s scale, without the dependency).
/// Everything else logs at the default level.
// ignore: public_member_api_docs -- a primary constructor has nowhere to hang a doc comment.
final class const PrintingBoxObserver({
  /// The DevTools-filterable logger name.
  final String name = 'hive_box_manager',
}) extends BoxObserver {
  /// SEVERE on `package:logging`'s level scale, minus the dependency.
  static const _errorLevel = 900;

  @override
  void onOpened(String boxName) => developer.log('Opened [$boxName]', name: name);

  @override
  void onClosed(String boxName) => developer.log('Closed [$boxName]', name: name);

  @override
  void onDeletedFromDisk(String boxName) =>
      developer.log('Deleted [$boxName] from disk', name: name);

  @override
  void onCleared(String boxName) => developer.log('Cleared [$boxName]', name: name);

  @override
  void onRead(String boxName, Object key, Object? value) =>
      developer.log('Read [$boxName] key=$key value=$value', name: name);

  @override
  void onReadAll(String boxName, int valueCount) =>
      developer.log('Read all of [$boxName] ($valueCount values)', name: name);

  @override
  void onWritten(String boxName, Object key, Object value) =>
      developer.log('Wrote [$boxName] key=$key value=$value', name: name);

  @override
  void onWrittenAll(String boxName, int entryCount) =>
      developer.log('Wrote $entryCount entries to [$boxName]', name: name);

  @override
  void onDeleted(String boxName, Object key) =>
      developer.log('Deleted [$boxName] key=$key', name: name);

  @override
  void onOperationError(String boxName, String operation, Object error, StackTrace stackTrace) =>
      developer.log(
        '$operation failed on [$boxName]',
        name: name,
        level: _errorLevel,
        error: error,
        stackTrace: stackTrace,
      );
}
