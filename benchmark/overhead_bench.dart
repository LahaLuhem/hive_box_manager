// Wrapper-overhead lane (build Phase 4): façade vs raw hive_ce on the hot paths aim #4
// protects, with the <5% target. One measurement per process invocation; emits one JSON line.
// Drive via overhead_driver.sh (JIT for sanity; `dart compile exe` + the driver for the
// deciding AOT numbers).
//
// Usage:
//   overhead_bench prep <n> <workDir>
//   overhead_bench get <impl> <n> <boxKind> <workDir>
//   overhead_bench put <impl> <n>
// with impl: facade | raw, boxKind: eager | lazy
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';

const boxName = 'bench';

/// Fixed seed for the random get-sample draw, keeping both impls on identical key sequences.
const getSampleSeed = 7;

/// Lazy gets pay a disk read per op, so that lane samples at most this many.
const maxLazyGetOps = 10000;

Future<void> main(List<String> args) async {
  switch (args) {
    case ['prep', final n, final workDir]:
      await runPrep(int.parse(n), workDir);
    case ['get', final impl, final n, final boxKind, final workDir]:
      await runGet(impl, int.parse(n), boxKind, workDir);
    case ['put', final impl, final n]:
      await runPut(impl, int.parse(n));
    default:
      throw ArgumentError.value(args.join(' '), 'args', 'unrecognised invocation');
  }
}

/// Builds the shared int-keyed box both impls read (constant 1-byte values, the P1 discipline).
Future<void> runPrep(int n, String workDir) async {
  Hive.init(workDir);
  final box = await Hive.openBox<String>(boxName);
  await box.putAll({for (var i = 0; i < n; i++) i: 'v'});
  await box.flush();
  await box.close();

  emit({'mode': 'prep', 'n': n});
}

Future<void> runGet(String impl, int n, String boxKind, String workDir) async {
  Hive.init(workDir);
  final random = Random(getSampleSeed);
  final sampleSize = boxKind == 'lazy' ? min(n, maxLazyGetOps) : n;
  final sampleKeys = List.generate(sampleSize, (_) => random.nextInt(n), growable: false);

  final stopwatch = Stopwatch();
  var checksum = 0;

  if (boxKind == 'eager' && impl == 'facade') {
    final box = await KeyedBox.open<String, int>(boxName).run();
    stopwatch.start();
    for (final key in sampleKeys) {
      checksum += box.get(key).toNullable()!.length;
    }
    stopwatch.stop();
  } else if (boxKind == 'eager') {
    final box = await Hive.openBox<String>(boxName);
    stopwatch.start();
    for (final key in sampleKeys) {
      checksum += box.get(key)!.length;
    }
    stopwatch.stop();
  } else if (impl == 'facade') {
    final box = LazyKeyedBox<String, int>(boxName);
    await box.ensureInitialised().run();
    stopwatch.start();
    for (final key in sampleKeys) {
      checksum += (await box.get(key).run()).toNullable()!.length;
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openLazyBox<String>(boxName);
    stopwatch.start();
    for (final key in sampleKeys) {
      checksum += (await box.get(key))!.length;
    }
    stopwatch.stop();
  }

  emit({
    'mode': 'get',
    'impl': impl,
    'n': n,
    'boxKind': boxKind,
    'ops': sampleSize,
    'micros': stopwatch.elapsedMicroseconds,
    'checksum': checksum,
  });
}

Future<void> runPut(String impl, int n) async {
  final workDir = Directory.systemTemp.createTempSync('hbm_overhead_put_');
  Hive.init(workDir.path);

  final stopwatch = Stopwatch();
  if (impl == 'facade') {
    final box = await KeyedBox.open<String, int>(boxName).run();
    stopwatch.start();
    for (var i = 0; i < n; i++) {
      await box.put(i, 'v').run();
    }
    stopwatch.stop();
    await box.close().run();
  } else {
    final box = await Hive.openBox<String>(boxName);
    stopwatch.start();
    for (var i = 0; i < n; i++) {
      await box.put(i, 'v');
    }
    stopwatch.stop();
    await box.close();
  }

  emit({'mode': 'put', 'impl': impl, 'n': n, 'micros': stopwatch.elapsedMicroseconds});
  workDir.deleteSync(recursive: true);
}

void emit(Map<String, Object> record) => stdout.writeln(jsonEncode(record));
