import 'package:hive_ce/hive.dart';

/// An enum for suites that need one: enums are restart-safe, so they work as ids and map keys.
enum Colour() {
  red,
}

/// Lets the integration suites put a [Colour] on disk.
final class const ColourAdapter() extends TypeAdapter<Colour> {
  @override
  int get typeId => 3;

  @override
  Colour read(BinaryReader reader) => Colour.values[reader.readByte()];

  @override
  void write(BinaryWriter writer, Colour obj) => writer.writeByte(obj.index);
}
