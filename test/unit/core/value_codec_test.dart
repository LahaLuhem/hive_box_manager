// The internal read/write-boundary seam: identity pass-through, and the #150 collection cast
// with its unmodifiable zero-copy view.
//
// The cast codec's whole subject is hive's `List<dynamic>` reification, so the DCM ban is
// lifted for this file.
// ignore_for_file: avoid-dynamic
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/value_codec.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

void main() {
  feature('IdentityValueCodec', () {
    scenario('passes values through untouched, both directions', () {
      const codec = IdentityValueCodec<String>();

      check(codec.toStorable('v')).equals('v');
      check(codec.fromStored('v')).equals('v');
    });
  });

  feature('CollectionCastValueCodec', () {
    scenario('restores element typing from a List<dynamic> disk shape', () {
      const codec = CollectionCastValueCodec<String>();
      final stored = <dynamic>['a', 'b'];

      final view = codec.fromStored(stored);

      check(view).isA<List<String>>();
      check(view.first).equals('a');
      check(view.length).equals(2);
    });

    scenario('the view is unmodifiable: consumers cannot reach the box cache through it', () {
      const codec = CollectionCastValueCodec<String>();
      final view = codec.fromStored(<dynamic>['a']);

      check(() => view.add('b')).throws<UnsupportedError>();
      check(view.clear).throws<UnsupportedError>();
    });

    scenario('the view is zero-copy: it follows the underlying list', () {
      const codec = CollectionCastValueCodec<String>();
      final backing = <dynamic>['a'];
      final view = codec.fromStored(backing);

      backing.add('b');

      check(view.length).equals(2);
      check(view.last).equals('b');
    });

    scenario("writes pass through untouched (materialisation is the façade's job)", () {
      const codec = CollectionCastValueCodec<String>();
      final value = ['a', 'b'];

      check(identical(codec.toStorable(value), value)).isTrue();
    });
  });
}
