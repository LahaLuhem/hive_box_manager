// The map-box demo through its view-model: a map of settings per user, against real hive on a temp
// dir.

import 'package:bdd_framework/bdd_framework.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/map_box/map_box_view_model.dart';

import '../../support/temp_hive.dart';

void main() {
  useTempHive('hbm_example_map_box_');
  late MapBoxViewModel sut;

  setUp(() {
    sut = MapBoxViewModel()..init();
  });

  tearDown(() => sut.onUnmount());

  /// Saves each of [settings] through the form, one at a time, the way a user would.
  Future<void> saveEach(Map<String, String> settings) async {
    for (final MapEntry(key: name, :value) in settings.entries) {
      sut.nameController.text = name;
      sut.valueController.text = value;
      await sut.onSavePressed();
    }
  }

  /// The listing in the order the screen shows it.
  List<(String, String)> listed() =>
      sut.settings.value.entries.map((entry) => (entry.key, entry.value)).toList();

  final feature = BddFeature('MapBox demo');

  Bdd(feature)
      .scenario('Saving a setting that is already there swaps its value in place.')
      .given('A user with 2 settings.')
      .when('The user saves the first one again with a new value.')
      .then('It takes the new value and keeps its place.')
      .example(
        val('seeded', {'theme': 'dark', 'language': 'en'}),
        val('saved', {'theme': 'light'}),
        val('listed', [('theme', 'light'), ('language', 'en')]),
      )
      .run((ctx) async {
        final seeded = ctx.example.val('seeded') as Map<String, String>;
        final saved = ctx.example.val('saved') as Map<String, String>;
        final expected = ctx.example.val('listed') as List<(String, String)>;
        await sut.ready;
        await saveEach(seeded);

        await saveEach(saved);

        check(listed()).deepEquals(expected);
      });

  Bdd(feature)
      .scenario('Removing a setting takes only that one out.')
      .given('A user with 2 settings.')
      .when('The user removes one of them.')
      .then('Only the other one is left.')
      .example(
        val('seeded', {'theme': 'dark', 'language': 'en'}),
        val('removed', 'theme'),
        val('left', [('language', 'en')]),
      )
      .run((ctx) async {
        final seeded = ctx.example.val('seeded') as Map<String, String>;
        final removed = ctx.example.val('removed') as String;
        final left = ctx.example.val('left') as List<(String, String)>;
        await sut.ready;
        await saveEach(seeded);

        await sut.onRemovePressed(removed);

        check(listed()).deepEquals(left);
      });

  Bdd(feature)
      .scenario('Each user has a map of their own.')
      .given('A setting saved for the first user.')
      .when('The screen switches to another user and back.')
      .then('The other user has no settings, and the first one still has theirs.')
      .example(val('saved', {'theme': 'dark'}), val('other user', 2), val('home user', 1))
      .run((ctx) async {
        final saved = ctx.example.val('saved') as Map<String, String>;
        final otherUser = ctx.example.val('other user') as int;
        final homeUser = ctx.example.val('home user') as int;
        await sut.ready;
        await saveEach(saved);

        sut.onUserSelected(otherUser);
        check(listed()).isEmpty();

        sut.onUserSelected(homeUser);
        check(sut.settings.value).deepEquals(saved);
      });
}
