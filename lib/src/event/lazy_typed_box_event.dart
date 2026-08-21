/// @docImport 'typed_box_event.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';

/// One change on a lazy box's watch stream: the decoded [key] and the [value] the engine could
/// actually deliver.
///
/// A `LazyBox` retains no values in memory, so hive_ce emits deletes and clears with no value attached
/// (pinned against 2.19.3). [value] is therefore `Some` for writes and `None` for deletes, and [deleted]
/// is derived from that instead of being stored twice. This is the honest lazy counterpart of
/// [TypedBoxEvent]'s non-null guarantee, mirroring how reads split across the axes (`Option` vs `TaskOption`).
@immutable
// ignore: public_member_api_docs -- a primary constructor has nowhere to hang a doc comment.
final class const LazyTypedBoxEvent<T extends Object, K extends Object>({
  /// The consumer-facing key, decoded by the box's key codec.
  required final K key,

  /// The written value, or `None` on a delete, where the engine has no value to hand over.
  required final Option<T> value,
}) {
  /// Whether this change removed [key] from the box; equivalently, whether [value] is `None`.
  bool get deleted => value.isNone();

  @override
  bool operator ==(Object other) =>
      other is LazyTypedBoxEvent<T, K> && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);

  @override
  String toString() => 'LazyTypedBoxEvent(key: $key, value: $value)';
}
