// The #150 collection cast with its unmodifiable zero-copy view.
//
// The cast codec's whole subject is hive's `List<dynamic>` reification, so the DCM ban is lifted for
// this file.
// ignore_for_file: avoid-dynamic
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/value_codec/collection_cast_value_codec.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  feature('CollectionCastValueCodec', () {
    scenario('restores element typing from a List<dynamic> disk shape', () {
      final codec = CollectionCastValueCodec<String>();
      final stored = <dynamic>['a', 'b'];

      final view = codec.fromStored(stored);

      check(view).isA<List<String>>();
      check(view.first).equals('a');
      check(view.length).equals(2);
    });

    scenario('elements of another type fail at the decode, not when touched', () async {
      final codec = CollectionCastValueCodec<int>();

      check(await thrownBy(() => codec.fromStored(<dynamic>[1, 'two']))).isA<TypeError>();
    });

    scenarioOutline<List<Object?>>(
      'the view is unmodifiable: consumers cannot reach the box cache through it',
      examples: {
        'read from disk': <dynamic>['a'],
        'already typed': <String>['a'],
      },
      outline: (stored) {
        final codec = CollectionCastValueCodec<String>();
        final view = codec.fromStored(stored);

        // `[0] =` because the box stores fixed-length copies, which refuse `add` even without the view.
        check(() => view[0] = 'b').throws<UnsupportedError>();
        check(() => view.add('b')).throws<UnsupportedError>();
      },
    );

    scenarioOutline<List<Object?>>(
      'the view is zero-copy: it follows the underlying list',
      examples: {
        'read from disk': <dynamic>['a'],
        'already typed': <String>['a'],
      },
      outline: (backing) {
        final codec = CollectionCastValueCodec<String>();
        final view = codec.fromStored(backing);

        backing.add('b');

        check(view.length).equals(2);
        check(view.last).equals('b');
      },
    );

    scenario("writes pass through untouched (materialisation is the façade's job)", () {
      final codec = CollectionCastValueCodec<String>();
      final value = ['a', 'b'];

      check(identical(codec.toStorable(value), value)).isTrue();
    });
  });
}
