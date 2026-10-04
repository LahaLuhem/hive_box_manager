/// A minimal custom type and adapter for the hive_ce pins, which need a registered [TypeAdapter] to
/// assert what the engine hands back for one.
library;

import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

/// A tiny value type with structural equality, so pins can assert round-trips.
@immutable
class const Person(final String name, final int age) {
  @override
  bool operator ==(Object other) => other is Person && other.name == name && other.age == age;

  @override
  int get hashCode => Object.hash(name, age);

  @override
  String toString() => 'Person($name, $age)';
}

/// Hand-written adapter: the pin suite pins engine truth, not generator output, so no codegen is involved.
class const PersonAdapter() extends TypeAdapter<Person> {
  @override
  int get typeId => 1;

  @override
  Person read(BinaryReader reader) => Person(reader.readString(), reader.readInt());

  @override
  void write(BinaryWriter writer, Person obj) => writer
    ..writeString(obj.name)
    ..writeInt(obj.age);
}
