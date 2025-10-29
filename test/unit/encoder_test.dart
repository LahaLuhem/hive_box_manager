import 'dart:io';
import 'dart:isolate';

import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:test/test.dart';

void main() {
  group('Encoder Tests', () {
    test('Range uniqueness', () async {
      final result = await _runParallelTest(6_000, isolates: 2);
      expect(result, isTrue);
    }, timeout: Timeout.none);
  }, timeout: Timeout.none);
}

Future<bool> _runParallelTest(int maxIndex, {int? isolates}) async {
  final numOfIsolates = isolates ?? Platform.numberOfProcessors;
  final batchSize = (maxIndex / numOfIsolates).ceil();
  final allFutures = <Future<Set<int>>>[];

  for (var i = 0; i < numOfIsolates; i++) {
    allFutures.add(
      Isolate.run(() {
        final localSet = <int>{};
        final start = i * batchSize;
        final end = (start + batchSize).clamp(0, maxIndex + 1);

        print('working on batch $i: $start to $end');

        for (var p = start; p < end; p++) {
          for (var s = 0; s <= maxIndex; s++) {
            final value = DualIntIndexLazyBoxManager.bitShiftEncoder(p, s);
            if (!localSet.add(value)) {
              throw TestFailure('Duplicate at ($p, $s) = $value');
            }
          }
        }

        print('batch $i done');

        return localSet;
      }),
    );
  }

  final results = await Future.wait(allFutures);
  final globalSet = <int>{};

  for (final set in results) {
    final before = globalSet.length;
    globalSet.addAll(set);
    if (globalSet.length != before + set.length) {
      throw TestFailure('Cross-batch duplicate detected');
    }
  }

  return true;
}
