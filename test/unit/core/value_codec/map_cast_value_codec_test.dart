// Hive's `Map<dynamic, dynamic>` is the subject here.
// ignore_for_file: avoid-dynamic
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/value_codec/map_cast_value_codec.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  feature('MapCastValueCodec', () {
    scenario('restores key and value typing from a Map<dynamic, dynamic> disk shape', () {
      final codec = MapCastValueCodec<String, int>();

      final view = codec.fromStored(<dynamic, dynamic>{'a': 1, 'b': 2});

      check(view).isA<Map<String, int>>();
      check(view).deepEquals({'a': 1, 'b': 2});
      check(view['b']).equals(2);
    });

    scenarioOutline<Map<dynamic, dynamic>>(
      'a key or value of another type fails at the decode, not when touched',
      examples: {
        'a key': <dynamic, dynamic>{'a': 1, 2: 2},
        'a value': <dynamic, dynamic>{'a': 1, 'b': 'two'},
      },
      outline: (stored) async {
        final codec = MapCastValueCodec<String, int>();

        check(await thrownBy(() => codec.fromStored(stored))).isA<TypeError>();
      },
    );

    scenarioOutline<Map<Object?, Object?>>(
      'the view is unmodifiable: consumers cannot reach the box cache through it',
      examples: {
        'read from disk': <dynamic, dynamic>{'a': 1},
        'already typed': <String, int>{'a': 1},
      },
      outline: (stored) {
        final codec = MapCastValueCodec<String, int>();
        final view = codec.fromStored(stored);

        check(() => view['b'] = 2).throws<UnsupportedError>();
        check(() => view.remove('a')).throws<UnsupportedError>();
      },
    );

    scenarioOutline<Map<Object?, Object?>>(
      'the view is zero-copy: it follows the underlying map',
      examples: {
        'read from disk': <dynamic, dynamic>{'a': 1},
        'already typed': <String, int>{'a': 1},
      },
      outline: (backing) {
        final codec = MapCastValueCodec<String, int>();
        final view = codec.fromStored(backing);

        backing['b'] = 2;

        check(view).deepEquals({'a': 1, 'b': 2});
      },
    );

    scenario("writes pass through untouched (materialisation is the façade's job)", () {
      final codec = MapCastValueCodec<String, int>();
      final value = {'a': 1};

      check(identical(codec.toStorable(value), value)).isTrue();
    });

    scenario('a value type hive hands back untyped fails the wiring assert', () {
      check(MapCastValueCodec<String, List<Person>>.new).throws<AssertionError>();
      check(MapCastValueCodec<String, List<String>>.new).returnsNormally();
    });
  });
}
