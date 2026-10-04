import 'package:flutter/widgets.dart' show TextEditingController;

/// Types each of [texts] into [field] and runs [submit] after each, the way a user adds entries one
/// at a time.
Future<void> enterEach(
  TextEditingController field,
  Future<void> Function() submit,
  Iterable<String> texts,
) async {
  for (final text in texts) {
    field.text = text;
    await submit();
  }
}
