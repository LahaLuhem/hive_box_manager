// P1 / P7 benchmark worker, migrated from the planning session's probe
// package. One measurement per process invocation; emits one JSON line.
//
// JIT: dart run benchmark/bench.dart <args>  (or benchmark/bench_jit.sh)
// AOT (the deciding lane): dart compile exe benchmark/bench.dart, then drive
// the executable via benchmark/driver.sh.
//
// Usage: bench <mode> <keyKind> <n> [boxKind] [workDir]
//   modes: put | putall | prep | open | get | scan | micro
//   keyKind: arith | string | bitshift
//   boxKind: eager | lazy
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:collection/collection.dart';
import 'package:hive_ce/hive.dart';

import 'key_codecs.dart';

const boxName = 'bench';

/// Fixed seed keeping pair generation identical across processes and runs.
const pairGenerationSeed = 42;

/// Fixed seed for the random get-sample draw.
const getSampleSeed = 7;

/// Lazy gets pay a disk read per op, so that lane samples at most this many.
const maxLazyGetOps = 10000;

/// putAll batching for the prep lane, bounding peak memory while building the batch map.
const prepChunkSize = 100000;

/// Which generated pair's primary the scan lane hunts (arbitrary; fixed for determinism).
const scanTargetPairIndex = 123;

/// Stride decorrelating the micro lane's secondary part from its primary.
const microSecondaryStride = 31;

Future<void> main(List<String> args) async {
  final mode = args.first;
  final keyKind = args[1];
  final n = int.parse(args[2]);
  final boxKind = args.length > 3 ? args[3] : 'eager';
  final workDir = args.length > 4 ? args[4] : '';

  switch (mode) {
    case 'put':
      await runPut(keyKind, n, isSingle: true);
    case 'putall':
      await runPut(keyKind, n, isSingle: false);
    case 'prep':
      await runPrep(keyKind, n, workDir);
    case 'open':
      await runOpen(keyKind, n, boxKind, workDir);
    case 'get':
      await runGet(keyKind, n, boxKind, workDir);
    case 'scan':
      await runScan(keyKind, n, workDir);
    case 'micro':
      runMicro(keyKind);
    default:
      throw ArgumentError('unknown mode: $mode');
  }
}

/// Deterministic distinct (primary, secondary) pairs, identical across processes (fixed seed).
List<(int, int)> generatePairs(int n) {
  final rng = Random(pairGenerationSeed);
  final seen = <int>{};
  final pairs = <(int, int)>[];
  while (pairs.length < n) {
    final primary = rng.nextInt(partCeiling);
    final secondary = rng.nextInt(partCeiling);
    if (seen.add(primary * partCeiling + secondary)) pairs.add((primary, secondary));
  }

  return pairs;
}

Object keyFor(String keyKind, (int, int) pair) => switch (keyKind) {
  'arith' => arithPack(pair.$1, pair.$2),
  'bitshift' => bitShiftPack(pair.$1, pair.$2),
  'string' => stringPack(pair.$1, pair.$2),
  _ => throw ArgumentError('unknown keyKind: $keyKind'),
};

void emit(Map<String, Object?> record) => stdout.writeln(jsonEncode(record));

Future<void> runPut(String keyKind, int n, {required bool isSingle}) async {
  final dir = Directory.systemTemp.createTempSync('hbm_bench_put_');
  Hive.init(dir.path);
  // Materialised: a lazy mapped Iterable re-runs keyFor on every traversal, which would both
  // double the encode work (batch build + timed loop) and move it inside the timed window.
  final keys = generatePairs(n).map((pair) => keyFor(keyKind, pair)).toList(growable: false);
  final box = await Hive.openBox<String>(boxName);

  // Immediately-consumed materialisation: the putAll batch, built outside the timed window.
  final batch = {for (final key in keys) key: 'v'};
  final watch = Stopwatch()..start();
  if (isSingle) {
    // Sequential by contract: this lane measures per-put round-trip latency; mapping to
    // futures + .wait would fire every put concurrently and measure throughput instead.
    for (final key in keys) {
      await box.put(key, 'v');
    }
  } else {
    await box.putAll(batch);
  }
  watch.stop();

  final fileBytes = File('${dir.path}/$boxName.hive').lengthSync();
  await Hive.close();
  dir.deleteSync(recursive: true);
  emit({
    'mode': isSingle ? 'put' : 'putall',
    'keyKind': keyKind,
    'n': n,
    'boxKind': 'eager',
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'fileBytes': fileBytes,
  });
}

Future<void> runPrep(String keyKind, int n, String workDir) async {
  Hive.init(workDir);
  final box = await Hive.openBox<String>(boxName);
  // slices() keeps the chunking lazy; each chunk's batch map is an immediately-consumed
  // materialisation.
  for (final chunk in generatePairs(n).slices(prepChunkSize)) {
    await box.putAll({for (final pair in chunk) keyFor(keyKind, pair): 'v'});
  }
  await box.flush();

  final fileBytes = File('$workDir/$boxName.hive').lengthSync();
  await Hive.close();
  emit({'mode': 'prep', 'keyKind': keyKind, 'n': n, 'fileBytes': fileBytes});
}

Future<void> runOpen(String keyKind, int n, String boxKind, String workDir) async {
  Hive.init(workDir);
  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  final box = boxKind == 'eager'
      ? await Hive.openBox<String>(boxName)
      : await Hive.openLazyBox<String>(boxName);
  watch.stop();
  final rssAfter = ProcessInfo.currentRss;

  final length = box.length;
  final fileBytes = File('$workDir/$boxName.hive').lengthSync();
  await Hive.close();
  emit({
    'mode': 'open',
    'keyKind': keyKind,
    'n': n,
    'boxKind': boxKind,
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'rssDeltaBytes': rssAfter - rssBefore,
    'fileBytes': fileBytes,
    'length': length,
  });
}

Future<void> runGet(String keyKind, int n, String boxKind, String workDir) async {
  Hive.init(workDir);
  final pairs = generatePairs(n);
  final rng = Random(getSampleSeed);
  final ops = boxKind == 'eager' ? n : min(n, maxLazyGetOps);
  // Materialised via generate: the draw is stateful (rng) and must run outside the timed loop.
  final sampleKeys = List.generate(ops, (_) => keyFor(keyKind, pairs[rng.nextInt(n)]));

  var checksum = 0;
  final watch = Stopwatch();
  if (boxKind == 'eager') {
    final box = await Hive.openBox<String>(boxName);
    watch.start();
    for (final key in sampleKeys) {
      checksum += box.get(key)!.length;
    }
    watch.stop();
  } else {
    final box = await Hive.openLazyBox<String>(boxName);
    watch.start();
    for (final key in sampleKeys) {
      checksum += (await box.get(key))!.length;
    }
    watch.stop();
  }

  await Hive.close();
  emit({
    'mode': 'get',
    'keyKind': keyKind,
    'n': n,
    'boxKind': boxKind,
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'ops': ops,
    'checksum': checksum,
  });
}

Future<void> runScan(String keyKind, int n, String workDir) async {
  Hive.init(workDir);
  final box = await Hive.openLazyBox<String>(boxName);
  final target = generatePairs(n)[scanTargetPairIndex].$1;

  var matches = 0;
  final watch = Stopwatch()..start();
  for (final key in box.keys) {
    final (primary, _) = switch (keyKind) {
      'arith' => arithUnpack(key as int),
      'bitshift' => bitShiftUnpack(key as int),
      'string' => stringUnpack(key as String),
      _ => throw ArgumentError('unknown keyKind: $keyKind'),
    };
    if (primary == target) matches++;
  }
  watch.stop();

  await Hive.close();
  emit({
    'mode': 'scan',
    'keyKind': keyKind,
    'n': n,
    'boxKind': 'lazy',
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'matches': matches,
  });
}

// This file is the worker entrypoint (`bench`, per driver.sh); the class is an internal harness
// detail, not the file's subject.
// ignore: prefer-match-file-name
class _PackUnpackBenchmark extends BenchmarkBase {
  _PackUnpackBenchmark(this.keyKind) : super('micro-$keyKind');

  final String keyKind;
  var checksum = 0;
  var counter = 0;

  @override
  void run() {
    final primary = counter & partMask;
    final secondary = (counter * microSecondaryStride) & partMask;
    switch (keyKind) {
      case 'arith':
        final (dp, ds) = arithUnpack(arithPack(primary, secondary));
        checksum += dp + ds;
      case 'bitshift':
        final (dp, ds) = bitShiftUnpack(bitShiftPack(primary, secondary));
        checksum += dp + ds;
      case 'string':
        final (dp, ds) = stringUnpack(stringPack(primary, secondary));
        checksum += dp + ds;
    }
    counter++;
  }
}

void runMicro(String keyKind) {
  final bench = _PackUnpackBenchmark(keyKind);
  final us = bench.measure();
  emit({'mode': 'micro', 'keyKind': keyKind, 'usPerMeasure': us, 'checksum': bench.checksum});
}
