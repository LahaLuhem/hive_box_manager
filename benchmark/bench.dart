// Key-codec matrix worker. One measurement per process invocation; emits one JSON line.
//
// Runs every lane twice, once per `impl`: `facade` drives the shipped `DualKeyBox` /
// `LazyDualKeyBox` with the shipped `DualKeyCodec`s, `raw` drives hive_ce directly with the
// hand-inlined pack/unpack in key_codecs.dart. The façade lane is what the README's performance
// table describes; the raw lane is both the historical baseline (the committed pre-1.0 results
// measured it) and the denominator for this lane's wrapper-overhead percentages.
//
// JIT: dart run benchmark/bench.dart <args>  (or benchmark/bench_jit.sh)
// AOT (the deciding lane): dart compile exe benchmark/bench.dart, then drive
// the executable via benchmark/driver.sh.
//
// Usage: bench <mode> <impl> <keyKind> <n> [boxKind] [workDir]
//   modes: put | putall | prep | open | get | scan | scanread | micro
//   impl: facade | raw
//   keyKind: arith | string | bitshift   (bitshift is raw-only: no shipped codec packs that way)
//   boxKind: eager | lazy
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:collection/collection.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
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

/// Which generated pair's primary the scan lanes hunt (arbitrary; fixed for determinism).
const scanTargetPairIndex = 123;

/// Stride decorrelating the micro lane's secondary part from its primary.
const microSecondaryStride = 31;

Future<void> main(List<String> args) async {
  final mode = args.first;
  final impl = args[1];
  final keyKind = args[2];
  final n = int.parse(args[3]);
  final boxKind = args.length > 4 ? args[4] : 'eager';
  final workDir = args.length > 5 ? args[5] : '';

  if (impl != 'facade' && impl != 'raw') throw ArgumentError('unknown impl: $impl');

  switch (mode) {
    case 'put':
      await runPut(impl, keyKind, n, isSingle: true);
    case 'putall':
      await runPut(impl, keyKind, n, isSingle: false);
    case 'prep':
      await runPrep(keyKind, n, workDir);
    case 'open':
      await runOpen(impl, keyKind, n, boxKind, workDir);
    case 'get':
      await runGet(impl, keyKind, n, boxKind, workDir);
    case 'scan':
      await runScan(keyKind, n, workDir);
    case 'scanread':
      await runScanRead(impl, keyKind, n, boxKind, workDir);
    case 'micro':
      runMicro(impl, keyKind);
    default:
      throw ArgumentError('unknown mode: $mode');
  }
}

/// The shipped codec matching [keyKind]. `bitshift` has none: [PackedIntDualCodec] is
/// byte-identical to it for in-range parts, so 0.0.x boxes read in place without a second codec,
/// and that lane stays raw-only as the byte-compatibility reference it always was.
DualKeyCodec<int, int> shippedCodecFor(String keyKind) => switch (keyKind) {
  'arith' => const PackedIntDualCodec(),
  'string' => const StringCompositeDualCodec(),
  'bitshift' => throw ArgumentError('bitshift is raw-only: no shipped codec packs that way'),
  _ => throw ArgumentError('unknown keyKind: $keyKind'),
};

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

Future<void> runPut(String impl, String keyKind, int n, {required bool isSingle}) async {
  final dir = Directory.systemTemp.createTempSync('hbm_bench_put_');
  Hive.init(dir.path);
  final pairs = generatePairs(n);
  final watch = Stopwatch();

  if (impl == 'facade') {
    final box = await DualKeyBox.open<String, int, int>(
      boxName,
      codec: shippedCodecFor(keyKind),
    ).run();
    // Immediately-consumed materialisation: the putAll batch, built outside the timed window.
    final batch = {for (final pair in pairs) pair: 'v'};
    watch.start();
    if (isSingle) {
      // Sequential by contract: this lane measures per-put round-trip latency; mapping to
      // futures + .wait would fire every put concurrently and measure throughput instead.
      for (final (primary, secondary) in pairs) {
        await box.put(primary, secondary, 'v').run();
      }
    } else {
      await box.putAll(batch).run();
    }
    watch.stop();
  } else {
    // Materialised: a lazy mapped Iterable re-runs keyFor on every traversal, which would both
    // double the encode work (batch build + timed loop) and move it inside the timed window.
    final keys = pairs.map((pair) => keyFor(keyKind, pair)).toList(growable: false);
    final box = await Hive.openBox<String>(boxName);
    final batch = {for (final key in keys) key: 'v'};
    watch.start();
    if (isSingle) {
      for (final key in keys) {
        await box.put(key, 'v');
      }
    } else {
      await box.putAll(batch);
    }
    watch.stop();
  }

  final fileBytes = File('${dir.path}/$boxName.hive').lengthSync();
  await Hive.close();
  dir.deleteSync(recursive: true);
  emit({
    'mode': isSingle ? 'put' : 'putall',
    'impl': impl,
    'keyKind': keyKind,
    'n': n,
    'boxKind': 'eager',
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'fileBytes': fileBytes,
  });
}

/// Builds the shared box the open / get / scan lanes read. Deliberately impl-agnostic: the
/// shipped codecs encode byte-identically to key_codecs.dart's pack functions (asserted by the
/// codec suites), so one prepped file serves both impls and the read lanes compare like for like.
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
  emit({'mode': 'prep', 'impl': 'shared', 'keyKind': keyKind, 'n': n, 'fileBytes': fileBytes});
}

Future<void> runOpen(String impl, String keyKind, int n, String boxKind, String workDir) async {
  Hive.init(workDir);
  final rssBefore = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  final int length;

  if (impl == 'facade' && boxKind == 'eager') {
    final box = await DualKeyBox.open<String, int, int>(
      boxName,
      codec: shippedCodecFor(keyKind),
    ).run();
    watch.stop();
    length = box.length;
  } else if (impl == 'facade') {
    // Lazy façades construct without touching disk, so the open this lane times is the
    // single-flight one ensureInitialised forces.
    final box = LazyDualKeyBox<String, int, int>(boxName, codec: shippedCodecFor(keyKind));
    await box.ensureInitialised().run();
    watch.stop();
    length = box.length;
  } else {
    final box = boxKind == 'eager'
        ? await Hive.openBox<String>(boxName)
        : await Hive.openLazyBox<String>(boxName);
    watch.stop();
    length = box.length;
  }
  final rssAfter = ProcessInfo.currentRss;

  final fileBytes = File('$workDir/$boxName.hive').lengthSync();
  await Hive.close();
  emit({
    'mode': 'open',
    'impl': impl,
    'keyKind': keyKind,
    'n': n,
    'boxKind': boxKind,
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'rssDeltaBytes': rssAfter - rssBefore,
    'fileBytes': fileBytes,
    'length': length,
  });
}

Future<void> runGet(String impl, String keyKind, int n, String boxKind, String workDir) async {
  Hive.init(workDir);
  final pairs = generatePairs(n);
  final rng = Random(getSampleSeed);
  final ops = boxKind == 'eager' ? n : min(n, maxLazyGetOps);
  // Materialised via generate: the draw is stateful (rng) and must run outside the timed loop.
  final samplePairs = List.generate(ops, (_) => pairs[rng.nextInt(n)], growable: false);

  var checksum = 0;
  final watch = Stopwatch();

  if (impl == 'facade' && boxKind == 'eager') {
    final box = await DualKeyBox.open<String, int, int>(
      boxName,
      codec: shippedCodecFor(keyKind),
    ).run();
    watch.start();
    for (final (primary, secondary) in samplePairs) {
      checksum += box.get(primary, secondary).toNullable()!.length;
    }
    watch.stop();
  } else if (impl == 'facade') {
    final box = LazyDualKeyBox<String, int, int>(boxName, codec: shippedCodecFor(keyKind));
    await box.ensureInitialised().run();
    watch.start();
    for (final (primary, secondary) in samplePairs) {
      checksum += (await box.get(primary, secondary).run()).toNullable()!.length;
    }
    watch.stop();
  } else {
    // Encoded *inside* the window, deliberately. A consumer holding a (user, day) pair builds the
    // composite key at the call site, exactly as the façade does, so pre-encoding the whole sample
    // outside the timed loop would hand the raw lane a discount no real workload gets. It did: the
    // earlier shape flattered raw and booked the difference as façade overhead.
    if (boxKind == 'eager') {
      final box = await Hive.openBox<String>(boxName);
      watch.start();
      for (final pair in samplePairs) {
        checksum += box.get(keyFor(keyKind, pair))!.length;
      }
      watch.stop();
    } else {
      final box = await Hive.openLazyBox<String>(boxName);
      watch.start();
      for (final pair in samplePairs) {
        checksum += (await box.get(keyFor(keyKind, pair)))!.length;
      }
      watch.stop();
    }
  }

  await Hive.close();
  emit({
    'mode': 'get',
    'impl': impl,
    'keyKind': keyKind,
    'n': n,
    'boxKind': boxKind,
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'ops': ops,
    'checksum': checksum,
  });
}

/// The historical count-only scan: decode every live key, count primary matches, read nothing.
/// Raw-only and kept verbatim so the committed pre-1.0 `results_aot.jsonl` scan rows stay
/// comparable. It is *not* the counterpart of `queryByPrimary`, which also reads each match;
/// that comparison is [runScanRead].
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
    'impl': 'raw',
    'keyKind': keyKind,
    'n': n,
    'boxKind': 'lazy',
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'matches': matches,
  });
}

/// A reverse query the way the API actually answers one: scan the live key set, then read every
/// match. The façade lane calls `queryByPrimary`; the raw lane hand-rolls the same two steps, so
/// the pair is a like-for-like wrapper-overhead measurement (unlike [runScan], which reads
/// nothing).
Future<void> runScanRead(String impl, String keyKind, int n, String boxKind, String workDir) async {
  Hive.init(workDir);
  final target = generatePairs(n)[scanTargetPairIndex].$1;

  final int matches;
  var checksum = 0;
  final watch = Stopwatch();

  if (impl == 'facade' && boxKind == 'eager') {
    final box = await DualKeyBox.open<String, int, int>(
      boxName,
      codec: shippedCodecFor(keyKind),
    ).run();
    watch.start();
    final hits = box.queryByPrimary(target);
    watch.stop();
    matches = hits.length;
    checksum = hits.fold(0, (sum, value) => sum + value.length);
  } else if (impl == 'facade') {
    final box = LazyDualKeyBox<String, int, int>(boxName, codec: shippedCodecFor(keyKind));
    await box.ensureInitialised().run();
    watch.start();
    final hits = await box.queryByPrimary(target).run();
    watch.stop();
    matches = hits.length;
    checksum = hits.fold(0, (sum, value) => sum + value.length);
  } else {
    final codec = shippedCodecFor(keyKind);
    if (boxKind == 'eager') {
      final box = await Hive.openBox<String>(boxName);
      watch.start();
      final hits = box.keys
          .where((key) => codec.decode(key as Object).$1 == target)
          .map((key) => box.get(key)!)
          .toList(growable: false);
      watch.stop();
      matches = hits.length;
      checksum = hits.fold(0, (sum, value) => sum + value.length);
    } else {
      final box = await Hive.openLazyBox<String>(boxName);
      watch.start();
      final hitKeys = box.keys
          .where((key) => codec.decode(key as Object).$1 == target)
          .toList(growable: false);
      // Parallel fetch: what the lazy façade's query does, so the baseline matches its shape.
      final hits = await Future.wait(hitKeys.map((key) async => (await box.get(key))!));
      watch.stop();
      matches = hits.length;
      checksum = hits.fold(0, (sum, value) => sum + value.length);
    }
  }

  await Hive.close();
  emit({
    'mode': 'scanread',
    'impl': impl,
    'keyKind': keyKind,
    'n': n,
    'boxKind': boxKind,
    'ms': watch.elapsedMicroseconds / Duration.microsecondsPerMillisecond,
    'matches': matches,
    'checksum': checksum,
  });
}

// This file is the worker entrypoint (`bench`, per driver.sh); the class is an internal harness
// detail, not the file's subject.
// ignore: prefer-match-file-name
class _PackUnpackBenchmark extends BenchmarkBase {
  new(this.impl, this.keyKind) : super('micro-$impl-$keyKind');

  final String impl;
  final String keyKind;

  /// Resolved once: the shipped codecs are const, so this is the dispatch the façade lane pays.
  late final DualKeyCodec<int, int>? codec = impl == 'facade' ? shippedCodecFor(keyKind) : null;

  var checksum = 0;
  var counter = 0;

  @override
  void run() {
    final primary = counter & partMask;
    final secondary = (counter * microSecondaryStride) & partMask;
    if (codec case final shippedCodec?) {
      final (dp, ds) = shippedCodec.decode(shippedCodec.encode(primary, secondary));
      checksum += dp + ds;
    } else {
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
    }
    counter++;
  }
}

void runMicro(String impl, String keyKind) {
  final bench = _PackUnpackBenchmark(impl, keyKind);
  final us = bench.measure();
  emit({
    'mode': 'micro',
    'impl': impl,
    'keyKind': keyKind,
    'usPerMeasure': us,
    'checksum': bench.checksum,
  });
}
