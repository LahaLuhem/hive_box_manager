import 'package:hive_ce/hive.dart';

/// Compares by identity, so only an `idOf` can tell 2 copies apart.
final class Member(final int id, final String name);

/// Lets the integration suites put a [Member] on disk.
final class const MemberAdapter() extends TypeAdapter<Member> {
  @override
  int get typeId => 2;

  @override
  Member read(BinaryReader reader) => Member(reader.readInt(), reader.readString());

  @override
  void write(BinaryWriter writer, Member obj) => writer
    ..writeInt(obj.id)
    ..writeString(obj.name);
}
