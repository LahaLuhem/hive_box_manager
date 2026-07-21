/// @docImport 'lazy_typed_box_event.dart';
library;

import 'package:meta/meta.dart';

/// One change on an eager box's watch stream: the decoded [key], the affected [value], and
/// whether the change [deleted] the entry.
///
/// The value is **non-null even on deletes**: eager hive_ce delivers the just-deleted value
/// from its cache (pinned against 2.19.3), so consumers never null-check and the 0.0.x
/// delete-event crash is unrepresentable. The lazy axis cannot make the same promise; its
/// stream carries [LazyTypedBoxEvent] instead.
@immutable
final class TypedBoxEvent<T extends Object, K extends Object> {
  /// Wraps one watch notification.
  const TypedBoxEvent({required this.key, required this.value, required this.deleted});

  /// The consumer-facing key, decoded by the box's key codec.
  final K key;

  /// The written value, or the just-deleted value when [deleted] is true.
  final T value;

  /// Whether this change removed [key] from the box.
  final bool deleted;

  @override
  bool operator ==(Object other) =>
      other is TypedBoxEvent<T, K> &&
      other.key == key &&
      other.value == value &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(key, value, deleted);

  @override
  String toString() => 'TypedBoxEvent(key: $key, value: $value, deleted: $deleted)';
}
