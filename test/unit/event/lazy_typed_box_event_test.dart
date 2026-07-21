// The lazy watch event: Option-valued, with `deleted` derived rather than stored twice.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive_box_manager/src/event/lazy_typed_box_event.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

void main() {
  feature('LazyTypedBoxEvent', () {
    scenario('deleted derives from the value: Some means written, None means deleted', () {
      const written = LazyTypedBoxEvent<String, int>(key: 7, value: Some('v'));
      const deleted = LazyTypedBoxEvent<String, int>(key: 7, value: None());

      check(written.deleted).isFalse();
      check(deleted.deleted).isTrue();
    });

    scenario('equality and hashCode are structural, through the Option', () {
      const event = LazyTypedBoxEvent<String, int>(key: 7, value: Some('v'));
      const same = LazyTypedBoxEvent<String, int>(key: 7, value: Some('v'));
      const gone = LazyTypedBoxEvent<String, int>(key: 7, value: None());

      check(event).equals(same);
      check(event.hashCode).equals(same.hashCode);
      check(event).not((it) => it.equals(gone));
    });

    scenario('toString names the key and the optional value', () {
      const event = LazyTypedBoxEvent<String, int>(key: 7, value: Some('v'));

      check(event.toString()).equals('LazyTypedBoxEvent(key: 7, value: Some(v))');
    });
  });
}
