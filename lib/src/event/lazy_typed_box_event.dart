/// @docImport 'typed_box_event.dart';
library;

import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';

/// One change on a lazy box's watch stream: the decoded [key] and the [value] the engine could actually
/// deliver.
///
/// A `LazyBox` keeps no values in memory, so hive_ce sends deletes and clears with nothing attached
/// (pinned behaviour). So [value] is `Some` on a write and `None` on a delete, and [deleted] reads off
/// that rather than being stored twice.
@immutable
// ignore: public_member_api_docs -- a primary constructor has nowhere to hang a doc comment.
final class const LazyTypedBoxEvent<T extends Object, K extends Object>({
  /// The consumer-facing key, decoded by the box's key codec.
  required final K key,

  /// The written value, or `None` on a delete, where there is nothing to hand over.
  required final Option<T> value,
}) {
  /// Whether this change removed [key], which is the same as [value] being `None`.
  bool get deleted => value.isNone();

  @override
  bool operator ==(Object other) =>
      other is LazyTypedBoxEvent<T, K> && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);

  @override
  String toString() => 'LazyTypedBoxEvent(key: $key, value: $value)';
}
