import 'package:meta/meta.dart';

/// Whether [value] still compares equal to the fresh copy a restart hands back.
@internal
bool isRestartSafeValue(Object value) =>
    value is String ||
    value is num ||
    value is bool ||
    value is Enum ||
    // A time's microseconds only survive inside the range hive stores exactly. Past it, the wrapper
    // leaves hive's rounding alone.
    value is DateTime ||
    value is Duration ||
    // A class that defines == has to define hashCode too, so one still on Object's own compares by
    // identity. Numbers, strings, bools and enums share that hash, which is why they go first.
    value.hashCode != identityHashCode(value);
