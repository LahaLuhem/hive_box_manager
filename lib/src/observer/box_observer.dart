import '/src/core/utils/no_op.dart';

/// Semantic observer over one or many boxes: extend it and override only the events you care about.
///
/// Everything is a no-op by default, and `base` means new events can land in a minor release without
/// breaking you. Attach one per box with `observer:`. With none attached a dispatch is one null check,
/// so it costs nothing. Dispatch is synchronous, so keep overrides cheap and hand IO or network work
/// to your own async code.
///
/// `boxName` comes first everywhere, so one observer can serve every box in an app.
abstract base class BoxObserver {
  /// Const so subclasses can be const-constructed and shared freely.
  const new();

  /// The box finished opening (an eager open, or a lazy box's first-use auto-open).
  void onOpened(String boxName) => noop();

  /// The box was closed. The handle is spent from here on.
  void onClosed(String boxName) => noop();

  /// The box's backing file (or IndexedDB store) was deleted from disk.
  void onDeletedFromDisk(String boxName) => noop();

  /// Every entry was removed in one clear.
  void onCleared(String boxName) => noop();

  /// A single-key read finished. [value] is null when the key wasn't there.
  void onRead(String boxName, Object key, Object? value) => noop();

  /// A whole-box read was served, [valueCount] entries at the time.
  void onReadAll(String boxName, int valueCount) => noop();

  /// A single-key write completed.
  void onWritten(String boxName, Object key, Object value) => noop();

  /// A batch write completed, spanning [entryCount] entries.
  void onWrittenAll(String boxName, int entryCount) => noop();

  /// A single-key delete completed (batch deletes report once per key).
  void onDeleted(String boxName, Object key) => noop();

  /// An effect failed. The error reaches the caller unchanged too.
  void onOperationError(String boxName, String operation, Object error, StackTrace stackTrace) =>
      noop();
}
