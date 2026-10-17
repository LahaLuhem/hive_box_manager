// IdentityValueCodec is a pure pass-through in both directions.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/value_codec/identity_value_codec.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  feature('IdentityValueCodec', () {
    scenario('passes values through untouched, both directions', () {
      const codec = IdentityValueCodec<String>();

      check(codec.toStorable('v')).equals('v');
      check(codec.fromStored('v')).equals('v');
    });
  });

  feature('the codec picked for a plain box', () {
    const changed = ProbeKeyLimits.firstWebImpreciseInt;
    const kept = (1 << 53) + 2;

    scenario(
      'a type that can hold an int gets it checked on writes, and reads stay as they are',
      () {
        final codec = identityCodecFor<int>();

        check(() => codec.toStorable(changed)).throws<ArgumentError>();
        check(codec.toStorable(kept)).equals(kept);
        check(codec.fromStored(changed)).equals(changed);
      },
    );

    scenario(
      "a type that can't hold an int gets the plain pass-through, so writes check nothing",
      () {
        check(identityCodecFor<String>().runtimeType).equals(IdentityValueCodec<String>);
      },
    );
  });
}
