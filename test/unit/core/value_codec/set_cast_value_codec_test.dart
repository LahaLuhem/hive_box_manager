// Hive's `Set<dynamic>` is the subject here.
// ignore_for_file: avoid-dynamic
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/value_codec/set_cast_value_codec.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  feature('SetCastValueCodec', () {
    scenario('restores element typing from a Set<dynamic> disk shape', () {
      final codec = SetCastValueCodec<String>();

      final view = codec.fromStored(<dynamic>{'a', 'b'});

      check(view).isA<Set<String>>();
      check(view).deepEquals({'a', 'b'});
      check(view.contains('b')).isTrue();
    });

    scenario('elements of another type fail at the decode, not when touched', () async {
      final codec = SetCastValueCodec<int>();

      check(await thrownBy(() => codec.fromStored(<dynamic>{1, 'two'}))).isA<TypeError>();
    });

    scenarioOutline<Set<Object?>>(
      'the view is unmodifiable: consumers cannot reach the box cache through it',
      examples: {
        'read from disk': <dynamic>{'a'},
        'already typed': <String>{'a'},
      },
      outline: (stored) {
        final codec = SetCastValueCodec<String>();
        final view = codec.fromStored(stored);

        check(() => view.add('b')).throws<UnsupportedError>();
        check(view.clear).throws<UnsupportedError>();
      },
    );

    scenarioOutline<Set<Object?>>(
      'the view is zero-copy: it follows the underlying set',
      examples: {
        'read from disk': <dynamic>{'a'},
        'already typed': <String>{'a'},
      },
      outline: (backing) {
        final codec = SetCastValueCodec<String>();
        final view = codec.fromStored(backing);

        backing.add('b');

        check(view).deepEquals({'a', 'b'});
      },
    );

    scenario("writes pass through untouched (materialisation is the façade's job)", () {
      final codec = SetCastValueCodec<String>();
      final value = {'a', 'b'};

      check(identical(codec.toStorable(value), value)).isTrue();
    });
  });
}
