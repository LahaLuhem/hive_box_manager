import 'package:hive_box_manager/src/codec/key/key_codec.dart';

/// A consumer-shaped codec for a key type with no identity default, driving the codec-defaulting
/// and custom-codec paths in the façade suites (ISO-8601 stays well under the 255-byte limit).
final class DateKeyCodec implements KeyCodec<DateTime> {
  const new();

  @override
  Object encode(DateTime key) => key.toIso8601String();

  @override
  DateTime decode(Object rawKey) => DateTime.parse(rawKey as String);
}
