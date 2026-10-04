/// Whether [T] is `String`, `num`, `bool` or an enum, the types that still compare equal after a restart
/// hands back fresh objects.
bool isRestartSafeType<T extends Object>() {
  // A type can't be tested directly, but an empty list of it can.
  final probe = <T>[];

  return probe is List<String> || probe is List<num> || probe is List<bool> || probe is List<Enum>;
}

/// [isRestartSafeType] for a value whose type is only known at run time.
bool isRestartSafeValue(Object? value) =>
    value is String || value is num || value is bool || value is Enum;
