import 'package:meta/meta.dart';

/// Whether a [T] still compares equal after a restart hands back fresh objects.
@internal
bool isRestartSafeType<T extends Object>() {
  // A type can't be tested directly, but an empty list of it can.
  final probe = <T>[];

  return probe is List<String> ||
      probe is List<num> ||
      probe is List<bool> ||
      probe is List<Enum> ||
      // A time's microseconds only survive inside the range hive stores exactly. Past it, the wrapper
      // leaves hive's rounding alone.
      probe is List<DateTime> ||
      probe is List<Duration>;
}

/// Whether [value] still compares equal to the fresh copy a restart hands back.
@internal
bool isRestartSafeValue(Object value) =>
    value is String ||
    value is num ||
    value is bool ||
    value is Enum ||
    value is DateTime ||
    value is Duration ||
    // A class that defines == has to define hashCode too, so one still on Object's own compares by
    // identity. Numbers, strings, bools and enums share that hash, which is why they go first.
    value.hashCode != identityHashCode(value);
