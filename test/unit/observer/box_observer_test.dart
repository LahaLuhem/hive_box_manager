// The observer base class: no-op defaults, partial override, const-constructibility, and the
// recording double the engine suites lean on.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/observer/box_observer.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/doubles/recording_box_observer.dart';

/// Overrides nothing: every dispatch must fall through to the no-op defaults.
// A test-helper double, not this file's subject (which is the suite itself).
// ignore: prefer-match-file-name
final class _SilentObserver extends BoxObserver {
  const _SilentObserver();
}

/// Overrides a single event: the partial-override consumer shape.
final class _WritesOnlyObserver extends BoxObserver {
  _WritesOnlyObserver();

  final writes = <String>[];

  @override
  void onWritten(String boxName, Object key, Object value) => writes.add('$boxName:$key:$value');
}

void _dispatchEverything(BoxObserver observer) {
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
}

void main() {
  feature('BoxObserver', () {
    scenario('a bare const subclass swallows every event silently', () {
      const observer = _SilentObserver();

      check(() => _dispatchEverything(observer)).returnsNormally();
    });

    scenario('partial override sees its event and nothing else breaks', () {
      final observer = _WritesOnlyObserver();

      _dispatchEverything(observer);

      check(observer.writes).deepEquals(['b:1:v']);
    });

    scenario('the recording double captures every event, in dispatch order', () {
      final observer = RecordingBoxObserver();

      _dispatchEverything(observer);

      check(observer.calls).deepEquals([
        'opened:b',
        'closed:b',
        'deletedFromDisk:b',
        'cleared:b',
        'read:b:1:v',
        'readAll:b:2',
        'written:b:1:v',
        'writtenAll:b:2',
        'deleted:b:1',
        'error:b:put:StateError',
      ]);
    });
  });
}
