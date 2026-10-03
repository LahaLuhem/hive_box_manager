@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/set/element_key.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

enum _Colour { red }

/// Compares by identity, Dart's default.
final class _Thing(final String id);

/// `==` by name only, so it's looser than an id key.
@immutable
final class const _Member(final int id, final String name) {
  @override
  bool operator ==(Object other) => other is _Member && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Generic, so each row resolves keyOf for its own type.
(Object, Object) _keyedByItself<T extends Object>(T sample) =>
    (sample, resolveKeyOf<T>(null)(sample));

void main() {
  feature('resolving keyOf while wiring', () {
    scenarioOutline<(Object, Object) Function()>(
      'a value-type element needs no keyOf and is its own key',
      examples: {
        'String': () => _keyedByItself('a'),
        'int': () => _keyedByItself(1),
        'double': () => _keyedByItself(1.5),
        'num': () => _keyedByItself<num>(1),
        'bool': () => _keyedByItself(true),
        'enum': () => _keyedByItself(_Colour.red),
      },
      outline: (resolve) {
        final (sample, key) = resolve();

        check(key).equals(sample);
      },
    );

    scenarioOutline<Object Function()>(
      'any other element type without keyOf fails the wiring assert',
      examples: {
        'identity ==': () => resolveKeyOf<_Thing>(null),
        'value ==': () => resolveKeyOf<_Member>(null),
        'Object': () => resolveKeyOf<Object>(null),
        'Comparable<String>': () => resolveKeyOf<Comparable<String>>(null),
      },
      outline: (resolve) => check(resolve).throws<AssertionError>(),
    );

    scenarioOutline<Object Function(_Thing)>(
      'keyOf may return any value type',
      examples: {
        'String': (thing) => thing.id,
        'int': (thing) => thing.id.length,
        'bool': (thing) => thing.id.isEmpty,
        'enum': (thing) => _Colour.red,
      },
      outline: (keyOf) {
        final thing = _Thing('a');

        check(resolveKeyOf<_Thing>(keyOf)(thing)).equals(keyOf(thing));
      },
    );

    scenarioOutline<Object Function(_Thing)>(
      'a keyOf returning anything else fails the key assert',
      examples: {
        'the element': (thing) => thing,
        'a list': (thing) => [thing.id],
        'a record': (thing) => (thing.id, 1),
      },
      outline: (keyOf) {
        final resolved = resolveKeyOf<_Thing>(keyOf);

        check(() => resolved(_Thing('a'))).throws<AssertionError>();
      },
    );
  });

  feature('deduplicating by key', () {
    String idOf(_Thing thing) => thing.id;

    scenario('keeps the first element per key, in encounter order', () {
      final first = _Thing('a');

      final deduped = dedupedByKey([first, _Thing('b'), _Thing('a')], idOf);

      check(deduped.map(idOf)).deepEquals(['a', 'b']);
      check(identical(deduped.first, first)).isTrue();
    });

    scenario('value types dedup by themselves', () {
      check(dedupedByKey(['a', 'b', 'a'], resolveKeyOf<String>(null))).deepEquals({'a', 'b'});
    });

    scenario("the result compares with the elements' own ==, not the key", () {
      final deduped = dedupedByKey([_Thing('a')], idOf);

      check(deduped.contains(_Thing('a'))).isFalse();
    });

    scenario('elements with different keys but equal == fail the merge assert', () {
      check(
        () => dedupedByKey([
          const _Member(1, 'Alex'),
          const _Member(2, 'Alex'),
        ], (member) => member.id),
      ).throws<AssertionError>();
    });
  });
}
