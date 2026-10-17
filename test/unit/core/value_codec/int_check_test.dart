@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/core/value_codec/int_check.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  const changed = ProbeKeyLimits.firstWebImpreciseInt;
  const kept = (1 << 53) + 2;

  feature('the int check a write runs, picked while wiring', () {
    scenarioOutline<IntCheck? Function()>(
      "a type that can't hold an int gets none",
      examples: {
        'String': intCheckFor<String>,
        'double': intCheckFor<double>,
        'bytes': intCheckFor<Uint8List>,
        'a list of strings': intCheckFor<List<String>>,
        'a map of strings': entriesCheckFor<String, String>,
        // Closures, as dart2wasm crashes on a const instantiation with a class nothing constructs.
        'a custom type': () => intCheckFor<Person>(),
        'elements of a custom type': () => elementsCheckFor<Person>(),
      },
      outline: (pick) => check(pick()).isNull(),
    );

    scenarioOutline<({IntCheck? intCheck, Object Function(int value) holding})>(
      'an int hive would change is refused wherever the type lets one sit, and one it keeps is not',
      examples: {
        'an int': (intCheck: intCheckFor<int>(), holding: (value) => value),
        'a num': (intCheck: intCheckFor<num>(), holding: (value) => value),
        'a list of ints': (intCheck: intCheckFor<List<int>>(), holding: (value) => [1, value]),
        'a set of ints': (intCheck: intCheckFor<Set<int>>(), holding: (value) => {1, value}),
        'the elements of a list of ints': (
          intCheck: elementsCheckFor<int>(),
          holding: (value) => [1, value],
        ),
        'lists inside a list': (
          intCheck: elementsCheckFor<List<int>>(),
          holding: (value) => [
            [value],
          ],
        ),
        'decoded JSON': (
          intCheck: intCheckFor<Map<Object?, Object?>>(),
          holding: (value) =>
              jsonDecode('{"items": [{"id": $value, "score": 1.5, "tags": ["a"]}], "next": null}')
                  as Object,
        ),
        'a key inside a dynamic map': (
          intCheck: intCheckFor<Map<Object?, Object?>>(),
          holding: (value) => <Object?, Object?>{value: 'x'},
        ),
        'an Object': (intCheck: intCheckFor<Object>(), holding: (value) => [value]),
        'a set of anything': (
          intCheck: intCheckFor<Set<Object?>>(),
          holding: (value) => <Object?>{'a', value},
        ),
        'the values of a map': (
          intCheck: entriesCheckFor<String, int>(),
          holding: (value) => {'k': value},
        ),
      },
      outline: (row) {
        check(() => row.intCheck!(row.holding(kept))).returnsNormally();
        check(() => row.intCheck!(row.holding(changed)))
            .throws<ArgumentError>()
            .has((error) => error.name, 'name')
            .equals('value');
      },
    );

    scenario('a map key hive would change is refused as a key', () {
      final entriesCheck = entriesCheckFor<int, String>()!;

      check(() => entriesCheck({kept: 'v'})).returnsNormally();
      check(() => entriesCheck({changed: 'v'}))
          .throws<ArgumentError>()
          .has((error) => error.name, 'name')
          .equals('key');
    });
  });
}
