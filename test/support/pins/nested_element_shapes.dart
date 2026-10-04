import 'dart:typed_data';

import 'package:hive_box_manager/src/core/value_codec/element_type_check.dart';
import 'package:hive_ce/hive.dart';

import '../fixtures/person.dart';
import '../harness/unique_box_name.dart';

/// What the wiring check says about an element shape, and what a reopen actually hands back.
typedef ShapeVerdicts = ({bool isAllowed, bool readsBackTyped});

/// The pins want the 2 verdicts to agree on every platform, so drift on either side fails loudly.
final Map<String, Future<ShapeVerdicts> Function()> nestedElementShapes = {
  'List<int>': () => _verdicts(<int>[1]),
  'List<double>': () => _verdicts(<double>[1.5]),
  'List<bool>': () => _verdicts(<bool>[true]),
  'List<String>': () => _verdicts(<String>['a']),
  'Set<int>': () => _verdicts(<int>{1}),
  'Set<double>': () => _verdicts(<double>{1.5}),
  'Set<String>': () => _verdicts(<String>{'a'}),
  'Uint8List': () => _verdicts(Uint8List.fromList([1])),
  'a custom type': () => _verdicts(const Person('ada', 36)),
  'List<Person>': () => _verdicts(const [Person('ada', 36)]),
  'List<num>': () => _verdicts(<num>[1, 1.5]),
  'Set<bool>': () => _verdicts(<bool>{true}),
  'Map<String, int>': () => _verdicts(<String, int>{'a': 1}),
  'Int32List': () => _verdicts(Int32List.fromList([1])),
};

Future<ShapeVerdicts> _verdicts<E extends Object>(E sample) async =>
    (isAllowed: isRestorableElementType<E>(), readsBackTyped: await _readsBackTyped(sample));

/// Stores [sample] both ways a box holds one, in a list and as a map value, and reopens before looking.
Future<bool> _readsBackTyped<E extends Object>(E sample) async {
  final boxName = uniqueBoxName('nested');
  final box = await Hive.openBox<Object>(boxName);
  await box.putAll({
    'in a list': [sample],
    'as a map value': {'key': sample},
  });
  await box.close();

  final reopened = await Hive.openBox<Object>(boxName);
  final readBack = [
    (reopened.get('in a list')! as List<Object?>).single,
    (reopened.get('as a map value')! as Map<Object?, Object?>).values.single,
  ];
  await reopened.deleteFromDisk();

  return readBack.every((element) => element is E);
}
