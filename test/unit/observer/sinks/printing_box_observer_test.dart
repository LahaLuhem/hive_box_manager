// Smoke-only, matching the sibling precedent: the sink is one-line forwards to dart:developer,
// whose output is not capturable from here; the suite pins that dispatch never throws.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/observer/sinks/printing_box_observer.dart';
import 'package:test/test.dart';

import '../../../support/bdd.dart';

void main() {
  feature('PrintingBoxObserver', () {
    scenario('every event forwards without throwing', () {
      const observer = PrintingBoxObserver();

      check(() {
        observer
          ..onOpened('b')
          ..onClosed('b')
          ..onDeletedFromDisk('b')
          ..onCleared('b')
          ..onRead('b', 1, 'v')
          ..onReadAll('b', 2)
          ..onWritten('b', 1, 'v')
          ..onWrittenAll('b', 2)
          ..onDeleted('b', 1)
          ..onOperationError('b', 'put', StateError('x'), StackTrace.empty);
      }).returnsNormally();
    });

    scenario('the logger name is configurable for DevTools filtering', () {
      const observer = PrintingBoxObserver(name: 'my_app.storage');

      check(observer.name).equals('my_app.storage');
    });
  });
}
