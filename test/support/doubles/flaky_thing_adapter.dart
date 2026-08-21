import 'package:hive_ce/hive.dart';

/// The record id whose read always fails, standing in for corrupt bytes or a newer build's format.
const undecodableId = 'bad';

/// hive's adapter registry is global and outlives `Hive.close()`, so suites register once, guarded.
const thingTypeId = 99;

/// Writes anything, refuses to read one record: a decode fault scoped to a single key.
final class FlakyThingAdapter extends TypeAdapter<Thing> {
  @override
  final typeId = thingTypeId;

  @override
  Thing read(BinaryReader reader) {
    final id = reader.readString();
    if (id == undecodableId) throw const FormatException('cannot decode this record');

    return Thing(id);
  }

  @override
  void write(BinaryWriter writer, Thing obj) => writer.writeString(obj.id);
}

/// A minimal adapter-backed value; [id] is all that reaches disk.
final class Thing {
  /// [undecodableId] here makes the adapter refuse this record.
  final String id;

  const new(this.id);

  @override
  String toString() => 'Thing($id)';
}
