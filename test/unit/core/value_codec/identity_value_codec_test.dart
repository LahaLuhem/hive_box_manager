// IdentityValueCodec is a pure pass-through in both directions.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/value_codec/identity_value_codec.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

void main() {
  feature('IdentityValueCodec', () {
    scenario('passes values through untouched, both directions', () {
      const codec = IdentityValueCodec<String>();

      check(codec.toStorable('v')).equals('v');
      check(codec.fromStored('v')).equals('v');
    });
  });
}
