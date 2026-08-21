import 'package:hive_box_manager/src/observer/box_observer.dart';

/// Records every dispatch as one readable line, so suites assert order and payloads in a single
/// `deepEquals` (the siblings' recording-observer pattern; the second sanctioned hand-written double).
final class RecordingBoxObserver extends BoxObserver {
  /// One line per dispatch, in dispatch order.
  final calls = <String>[];

  /// Non-const: [calls] is per-instance mutable state.
  new();

  @override
  void onOpened(String boxName) => calls.add('opened:$boxName');

  @override
  void onClosed(String boxName) => calls.add('closed:$boxName');

  @override
  void onDeletedFromDisk(String boxName) => calls.add('deletedFromDisk:$boxName');

  @override
  void onCleared(String boxName) => calls.add('cleared:$boxName');

  @override
  void onRead(String boxName, Object key, Object? value) => calls.add('read:$boxName:$key:$value');

  @override
  void onReadAll(String boxName, int valueCount) => calls.add('readAll:$boxName:$valueCount');

  @override
  void onWritten(String boxName, Object key, Object value) =>
      calls.add('written:$boxName:$key:$value');

  @override
  void onWrittenAll(String boxName, int entryCount) => calls.add('writtenAll:$boxName:$entryCount');

  @override
  void onDeleted(String boxName, Object key) => calls.add('deleted:$boxName:$key');

  @override
  void onOperationError(String boxName, String operation, Object error, StackTrace stackTrace) =>
      calls.add('error:$boxName:$operation:${error.runtimeType}');
}
