/// One stored value could not be decoded, naming the [key] whose record failed.
///
/// Whole-box and scan reads wrap. A single-key read already fails at a known key, so that one lets [cause]
/// through untouched.
// ignore: public_member_api_docs -- a primary constructor has nowhere to hang a doc comment.
final class const UndecodableValueException({
  /// The box holding the record, as observers hear it.
  required final String boxName,

  /// The failing key, as this box's consumers see it.
  required final Object key,

  /// The adapter's or value codec's own error, unchanged.
  required final Object cause,
}) implements Exception {
  @override
  String toString() => 'UndecodableValueException(box: $boxName, key: $key): $cause';
}
