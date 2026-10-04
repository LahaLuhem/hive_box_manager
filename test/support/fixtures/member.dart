import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';

/// Compares by identity, so only an `idOf` can tell 2 copies apart.
final class Member(final int id, final String name);

/// What a check compares, since a [Member] only equals itself.
extension MemberNames on Iterable<Member> {
  /// Each member's name, in iteration order.
  Iterable<String> get names => map((member) => member.name);
}

/// [MemberNames] for a lazy box, which has to read the set off disk first.
extension LazyMemberNames on LazySetBox<Member, int> {
  /// The names stored under [key].
  Future<Iterable<String>> namesUnder(int key) async => (await getOr(key).run()).names;
}

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
