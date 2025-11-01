import 'dart:io';
import 'dart:isolate';

import 'package:dart_bloom_filter/dart_bloom_filter.dart';
import 'package:fpdart/fpdart.dart';
import 'package:test/test.dart';

typedef ValueCheck = void Function(int primary, int secondary, int value);
typedef IndexGenerator = Iterable<int> Function(int maxIndex);

Future<bool> runParallelEncoderTest({
  required int Function(int primary, int secondary) encoder,
  required int maxIndex,
  required IndexGenerator primaryIndexGenerator,
  required IndexGenerator secondaryIndexGenerator,
  List<ValueCheck> additionalChecks = const [],
  int? isolates,
}) async {
  final numOfIsolates = isolates ?? Platform.numberOfProcessors;
  print('Running on $numOfIsolates isolates');

  // Generate all indices for both dimensions
  final allPrimaryIndices = primaryIndexGenerator(maxIndex).toList();
  final allSecondaryIndices = secondaryIndexGenerator(maxIndex).toList();

  final totalPrimary = allPrimaryIndices.length;
  final batchSize = (totalPrimary / numOfIsolates).ceil();

  print('Primary indices: ${allPrimaryIndices.length} values');
  print('Secondary indices: ${allSecondaryIndices.length} values');
  print('Total combinations: ${allPrimaryIndices.length * allSecondaryIndices.length}');
  print('Batch size: $batchSize');

  final allFutures = Iterable.generate(
    numOfIsolates,
    (i) => Isolate.run(() {
      final localSet = <int>{};

      // Calculate batch range for primary indices
      final start = i * batchSize;
      final end = (start + batchSize).clamp(0, totalPrimary);

      print('working on batch $i: primary indices $start to $end');
      // Test all combinations: primary from batch range, secondary from all
      for (var pIndex = start; pIndex < end; pIndex++) {
        final primary = allPrimaryIndices[pIndex];
        for (final secondary in allSecondaryIndices) {
          final value = encoder(primary, secondary);

          // Mandatory check 1: Max 32-bit range
          if (value > 0xFFFFFFFF - 1) {
            throw TestFailure('Overflow at ($primary, $secondary) = $value');
          }

          // Run additional custom checks
          for (final check in additionalChecks) {
            check(primary, secondary, value);
          }

          // Mandatory check 2: Local uniqueness
          if (!localSet.add(value)) {
            throw TestFailure('Duplicate at ($primary, $secondary) = $value');
          }
        }
      }
      print('batch $i done');

      return localSet;
    }),
  );

  final results = await Future.wait(allFutures);

  // Mandatory check 3: Global duplicates using Bloom filter
  final expectedElements = allPrimaryIndices.length * allSecondaryIndices.length;
  final globalBloomSet = BloomFilter<int>(expectedElements, 0.001);

  for (final set in results) {
    final before = globalBloomSet.length;
    globalBloomSet.addAll(items: set.toList(growable: false));

    if (globalBloomSet.length != before + set.length) {
      throw TestFailure('Cross-batch duplicate detected');
    }
  }

  return true;
}

// For positive indices only (0 to maxIndex)
Iterable<int> positiveIndexGenerator(int maxIndex) => Iterable.generate(maxIndex);

// For negative and positive indices (-maxIndex to maxIndex)
Iterable<int> signedIndexGenerator(int maxIndex) =>
    Iterable.generate(maxIndex * 2, (i) => i - maxIndex).append(maxIndex);

Iterable<int> customRangeIndexGenerator(int start, int end) sync* {
  for (var i = start; i <= end; i++) {
    yield i;
  }
}
