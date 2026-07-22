import '/src/core/utils/no_op.dart';

/// Semantic observer over one or many boxes: extend it and override only the events you care about.
///
/// Every method is a no-op by default, so subclasses stay minimal, and `base` (extend, never implement)
/// lets new events land in minor releases without breaking anyone. Attach one per box at construction
/// (`observer:`); with none attached, dispatch is a single null check, so the silent default costs
/// nothing on hot paths. Dispatch is synchronous: keep overrides cheap, and push expensive sink work
/// (IO, network) onto your own asynchronous machinery.
///
/// `boxName` leads every signature so a single observer instance can serve every box in an app.
abstract base class BoxObserver {
  /// Const so subclasses can be const-constructed and shared freely.
  const BoxObserver();

  /// The box finished opening (an eager open, or a lazy box's first-use auto-open).
  void onOpened(String boxName) => noop();

  /// The box was closed; the handle is terminal from here on.
  void onClosed(String boxName) => noop();

  /// The box's backing file (or IndexedDB store) was deleted from disk.
  void onDeletedFromDisk(String boxName) => noop();

  /// Every entry was removed in one clear.
  void onCleared(String boxName) => noop();

  /// A single-key read completed; [value] is null when the key was absent.
  void onRead(String boxName, Object key, Object? value) => noop();

  /// A whole-box read was served, spanning [valueCount] entries at that moment.
  void onReadAll(String boxName, int valueCount) => noop();

  /// A single-key write completed.
  void onWritten(String boxName, Object key, Object value) => noop();

  /// A batch write completed, spanning [entryCount] entries.
  void onWrittenAll(String boxName, int entryCount) => noop();

  /// A single-key delete completed (batch deletes report once per key).
  void onDeleted(String boxName, Object key) => noop();

  /// An operation's effect failed; the error also propagates to the caller unchanged.
  void onOperationError(String boxName, String operation, Object error, StackTrace stackTrace) =>
      noop();
}
