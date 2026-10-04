/// One stored value could not be decoded, naming the [key] whose record failed.
///
/// Whole-box and scan reads wrap. A single-key read already fails at a known key, so that one lets [cause]
/// through untouched.
final class const UndecodableValueException({
  /// The box holding the record, as observers hear it.
  required final String boxName,

  /// The failing key, as this box's consumers see it.
  required final Object key,

  /// The adapter's or value codec's own error, unchanged.
  required final Object cause,
}) implements Exception {
  /// The engines throw this. Build one yourself only to fake a decode failure in a test.
  this;

  @override
  String toString() => 'UndecodableValueException(box: $boxName, key: $key): $cause';
}
