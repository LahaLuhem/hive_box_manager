@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/set/element_id.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

// A test fixture, not this file's subject.
// ignore: prefer-match-file-name
enum _Colour() {
  red,
}

/// Compares by identity, Dart's default.
final class _Thing(final String id);

/// `==` by name only, so it's looser than an id.
@immutable
final class const _Member(final int id, final String name) {
  @override
  bool operator ==(Object other) => other is _Member && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Generic, so each row resolves idOf for its own type.
(Object, Object) _identifiedByItself<T extends Object>(T sample) =>
    (sample, resolveIdOf<T>(null)(sample));

void main() {
  feature('resolving idOf while wiring', () {
    scenarioOutline<(Object, Object) Function()>(
      'a value-type element needs no idOf and is its own id',
      examples: {
        'String': () => _identifiedByItself('a'),
        'int': () => _identifiedByItself(1),
        'double': () => _identifiedByItself(1.5),
        'num': () => _identifiedByItself<num>(1),
        'bool': () => _identifiedByItself(true),
        'enum': () => _identifiedByItself(_Colour.red),
      },
      outline: (resolve) {
        final (sample, id) = resolve();

        check(id).equals(sample);
      },
    );

    scenarioOutline<Object Function()>(
      'any other element type without idOf fails the wiring assert',
      examples: {
        'identity ==': () => resolveIdOf<_Thing>(null),
        'value ==': () => resolveIdOf<_Member>(null),
        'Object': () => resolveIdOf<Object>(null),
        'Comparable<String>': () => resolveIdOf<Comparable<String>>(null),
      },
      outline: (resolve) => check(resolve).throws<AssertionError>(),
    );

    scenarioOutline<Object Function(_Thing)>(
      'idOf may return any value type',
      examples: {
        'String': (thing) => thing.id,
        'int': (thing) => thing.id.length,
        'bool': (thing) => thing.id.isEmpty,
        'enum': (thing) => _Colour.red,
      },
      outline: (idOf) {
        final thing = _Thing('a');

        check(resolveIdOf<_Thing>(idOf)(thing)).equals(idOf(thing));
      },
    );

    scenarioOutline<Object Function(_Thing)>(
      'an idOf returning anything else fails the id assert',
      examples: {
        'the element': (thing) => thing,
        'a list': (thing) => [thing.id],
        'a record': (thing) => (thing.id, 1),
      },
      outline: (idOf) {
        final resolved = resolveIdOf<_Thing>(idOf);

        check(() => resolved(_Thing('a'))).throws<AssertionError>();
      },
    );
  });

  feature('deduplicating by id', () {
    String idOf(_Thing thing) => thing.id;

    scenario('keeps the first element per id, in encounter order', () {
      final first = _Thing('a');

      final deduped = dedupedById([first, _Thing('b'), _Thing('a')], idOf);

      check(deduped.map(idOf)).deepEquals(['a', 'b']);
      check(identical(deduped.first, first)).isTrue();
    });

    scenario('value types dedup by themselves', () {
      check(dedupedById(['a', 'b', 'a'], resolveIdOf<String>(null))).deepEquals({'a', 'b'});
    });

    scenario("the result compares with the elements' own ==, not the id", () {
      final deduped = dedupedById([_Thing('a')], idOf);

      check(deduped.contains(_Thing('a'))).isFalse();
    });

    scenario('elements with different ids but equal == fail the merge assert', () {
      check(
        () => dedupedById([
          const _Member(1, 'Alex'),
          const _Member(2, 'Alex'),
        ], (member) => member.id),
      ).throws<AssertionError>();
    });
  });

  feature('upserting by id', () {
    String idOf(_Thing thing) => thing.id;

    scenario('replaces a stored element with the same id where it sits', () {
      final replacement = _Thing('b');

      final upserted = upsertedById([_Thing('a'), _Thing('b'), _Thing('c')], [replacement], idOf);

      check(upserted.map(idOf)).deepEquals(['a', 'b', 'c']);
      check(identical(upserted.elementAt(1), replacement)).isTrue();
    });

    scenario('puts new ids on the end, in encounter order', () {
      final upserted = upsertedById([_Thing('a')], [_Thing('c'), _Thing('b')], idOf);

      check(upserted.map(idOf)).deepEquals(['a', 'c', 'b']);
    });

    scenario('within one call, the first incoming element per id wins', () {
      final first = _Thing('a');

      final upserted = upsertedById([_Thing('a')], [first, _Thing('a')], idOf);

      check(identical(upserted.single, first)).isTrue();
    });
  });
}
