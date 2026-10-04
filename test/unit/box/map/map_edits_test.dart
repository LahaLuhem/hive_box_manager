@Tags(['unit'])
library;

import 'dart:collection';

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/box/map/map_edits.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  feature('the map write copy', () {
    scenario('later edits to the source never reach the copy, and order is kept', () {
      final source = {'b': 2, 'a': 1};

      final copy = storableCopyOf(source);
      source['c'] = 3;

      check(copy.keys).deepEquals(['b', 'a']);
    });

    scenario("the copy drops the source's own equality, as a restart would", () {
      final caseInsensitive = LinkedHashMap<String, int>(
        equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
        hashCode: (key) => key.toLowerCase().hashCode,
      )..['Ada'] = 1;

      check(storableCopyOf(caseInsensitive)['ADA']).isNull();
    });

    scenarioOutline<Map<Object, String> Function()>(
      "an int key hive can't store exactly fails at the call",
      examples: {
        'int keys': () => storableCopyOf<int, String>({ProbeKeyLimits.firstWebImpreciseInt: 'a'}),
        'num keys': () => storableCopyOf<num, String>({ProbeKeyLimits.firstWebImpreciseInt: 'a'}),
      },
      outline: (copy) => check(copy).throws<ArgumentError>(),
    );
  });
}
