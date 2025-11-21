/// @docImport 'package:hive_ce/hive.dart';
library;

import 'package:meta/meta.dart';

/// Typed version of [BoxEvent]
@immutable
final class TypedBoxEvent<T, I extends Object> {
  final I index;
  final T value;

  final bool deleted;

  const TypedBoxEvent({required this.index, required this.value, required this.deleted});

  @override
  bool operator ==(Object other) {
    if (other is TypedBoxEvent) return other.index == index && other.value == value;

    return false;
  }

  @override
  int get hashCode => runtimeType.hashCode ^ index.hashCode ^ value.hashCode;
}
