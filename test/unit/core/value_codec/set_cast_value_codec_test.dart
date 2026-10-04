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
      const codec = SetCastValueCodec<String>();

      final view = codec.fromStored(<dynamic>{'a', 'b'});

      check(view).isA<Set<String>>();
      check(view).deepEquals({'a', 'b'});
      check(view.contains('b')).isTrue();
    });

    scenario('the view is unmodifiable: consumers cannot reach the box cache through it', () {
      const codec = SetCastValueCodec<String>();
      final view = codec.fromStored(<dynamic>{'a'});

      check(() => view.add('b')).throws<UnsupportedError>();
      check(view.clear).throws<UnsupportedError>();
    });

    scenario('the view is zero-copy: it follows the underlying set', () {
      const codec = SetCastValueCodec<String>();
      final backing = <dynamic>{'a'};
      final view = codec.fromStored(backing);

      backing.add('b');

      check(view).deepEquals({'a', 'b'});
    });

    scenario("writes pass through untouched (materialisation is the façade's job)", () {
      const codec = SetCastValueCodec<String>();
      final value = {'a', 'b'};

      check(identical(codec.toStorable(value), value)).isTrue();
    });
  });
}
