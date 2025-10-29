import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:dart_bloom_filter/dart_bloom_filter.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:shouldly/shouldly_bool.dart';
import 'package:test/test.dart';

void main() {
  group('Encoder Tests', () {
    test('Range uniqueness (Just a formality. Mathematically proven.)', () async {
      final result = await _runParallelTest(20_000);
      result.should.beTrue();
    }, timeout: Timeout.none);
  }, timeout: Timeout.none);
}

Future<bool> _runParallelTest(int maxIndex, {int? isolates}) async {
  final numOfIsolates = isolates ?? Platform.numberOfProcessors;
  print('Running on $numOfIsolates isolates');
  final batchSize = (maxIndex / numOfIsolates).ceil();
  print('Batch size: $batchSize');

  final allFutures = Iterable.generate(
    numOfIsolates,
    (i) => Isolate.run(() {
      final localSet = <int>{};
      final start = i * batchSize;
      final end = (start + batchSize).clamp(0, maxIndex + 1);

      print('working on batch $i: $start to $end');

      for (var p = start; p < end; p++) {
        for (var s = 0; s <= maxIndex; s++) {
          final value = DualIntIndexLazyBoxManager.bitShiftEncoder(p, s);
          if (!localSet.add(value)) throw TestFailure('Duplicate at ($p, $s) = $value');
        }
      }

      print('batch $i done');

      return localSet;
    }),
  );

  final results = await Future.wait(allFutures);
  // Create bloom filter with estimated size and acceptable false positive rate
  final expectedElements = pow(maxIndex + 1, 2).toInt();
  final globalBloomSet = BloomFilter<int>(expectedElements, 0.001); // 0.1% false positive rate

  for (final set in results) {
    final before = globalBloomSet.length;
    globalBloomSet.addAll(items: set.toList(growable: false));
    if (globalBloomSet.length != before + set.length) {
      throw TestFailure('Cross-batch duplicate detected');
    }
  }

  return true;
}
