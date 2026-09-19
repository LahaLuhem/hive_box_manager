/// @docImport 'lazy_typed_box_event.dart';
library;

import 'package:meta/meta.dart';

/// One change on an eager box's watch stream: the decoded [key], the affected [value], and whether the
/// change [deleted] the entry.
///
/// The value is there even on deletes, because eager hive_ce hands back what it just dropped from its
/// cache (pinned behaviour), so there is nothing to null-check. A lazy box can't promise that, so it
/// carries [LazyTypedBoxEvent] instead.
@immutable
// ignore: public_member_api_docs -- a primary constructor has nowhere to hang a doc comment.
final class const TypedBoxEvent<T extends Object, K extends Object>({
  /// The consumer-facing key, decoded by the box's key codec.
  required final K key,

  /// The written value, or the just-deleted value when [deleted] is true.
  required final T value,

  /// Whether this change removed [key] from the box.
  required final bool deleted,
}) {
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
