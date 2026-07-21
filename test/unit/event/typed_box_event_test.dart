// The eager watch event: a plain immutable value type with structural equality.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/event/typed_box_event.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

void main() {
  feature('TypedBoxEvent', () {
    scenario('equality and hashCode are structural', () {
      const event = TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: false);
      const same = TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: false);
      const otherDeleted = TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: true);
      const otherKey = TypedBoxEvent<String, int>(key: 8, value: 'v', deleted: false);

      check(event).equals(same);
      check(event.hashCode).equals(same.hashCode);
      check(event).not((it) => it.equals(otherDeleted));
      check(event).not((it) => it.equals(otherKey));
    });

    scenario('toString names every field for log-worthiness', () {
      const event = TypedBoxEvent<String, int>(key: 7, value: 'v', deleted: true);

      check(event.toString()).equals('TypedBoxEvent(key: 7, value: v, deleted: true)');
    });
  });
}
