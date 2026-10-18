@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/set/element_id.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

/// Compares by identity, Dart's default.
// A test fixture, not this file's subject.
// ignore: prefer-match-file-name
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
  feature('resolving idOf', () {
    scenarioOutline<(Object, Object) Function()>(
      'an element that compares by value needs no idOf and is its own id',
      examples: {
        'String': () => _identifiedByItself('a'),
        'int': () => _identifiedByItself(1),
        'double': () => _identifiedByItself(1.5),
        'num': () => _identifiedByItself<num>(1),
        'bool': () => _identifiedByItself(true),
        'enum': () => _identifiedByItself(Colour.red),
        'DateTime': () => _identifiedByItself(DateTime.utc(2026, 10, 3, 12, 0, 0, 0, 1)),
        'Duration': () => _identifiedByItself(const Duration(microseconds: 7)),
        'a class with its own ==': () => _identifiedByItself(const _Member(1, 'Alex')),
        'a String held as an Object': () => _identifiedByItself<Object>('a'),
      },
      outline: (resolve) {
        final (sample, id) = resolve();

        check(id).equals(sample);
      },
    );

    scenarioOutline<Object Function(_Thing) Function()>(
      'without idOf, an element that compares by identity fails the assert at its first id',
      examples: {
        'a class without its own ==': () => resolveIdOf<_Thing>(null),
        'one held as an Object': () => resolveIdOf<Object>(null),
      },
      outline: (resolve) {
        final identify = resolve();

        check(() => identify(_Thing('a'))).throws<AssertionError>();
      },
    );

    scenarioOutline<Object Function(_Thing)>(
      'idOf may return anything that compares by value',
      examples: {
        'String': (thing) => thing.id,
        'int': (thing) => thing.id.length,
        'bool': (thing) => thing.id.isEmpty,
        'enum': (thing) => Colour.red,
        'DateTime': (thing) => DateTime.utc(2026, 10, 3, 12, 0, 0, 0, 1),
        'Duration': (thing) => Duration(microseconds: thing.id.length),
        'a record': (thing) => (thing.id, 1),
        'a class with its own ==': (thing) => _Member(1, thing.id),
      },
      outline: (idOf) {
        final thing = _Thing('a');

        check(resolveIdOf<_Thing>(idOf)(thing)).equals(idOf(thing));
      },
    );

    scenarioOutline<Object Function(_Thing)>(
      'an idOf returning something that compares by identity fails the id assert',
      examples: {
        'the element': (thing) => thing,
        'a list': (thing) => [thing.id],
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
