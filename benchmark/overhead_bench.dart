// Wrapper-overhead lane: façade vs raw hive_ce on the hot paths aim #4 protects. The target is
// two-currency, since a flat percentage says nothing on an op that costs 13 ns raw: tens of
// nanoseconds per op on the memory paths, single-digit percent on anything reaching disk.
// One measurement per process invocation; emits one JSON line.
// Drive via overhead_driver.sh (JIT for sanity; `dart compile exe` + the driver for the
// deciding AOT numbers).
//
// Every lane here compares operations with an *exact* raw counterpart, so the percentage means
// "what the wrapper costs" and nothing else. `ListBox` and `DualKeyBox` are deliberately absent:
// raw hive_ce has no equivalent of a list-valued or two-part-keyed box, so their baseline has to be
// hand-rolled code rather than one call, which is a different question measured elsewhere (the
// matrix lane covers dual; the list box has its own lane).
//
// Usage:
//   overhead_bench prep <n> <workDir>
//   overhead_bench get <impl> <n> <boxKind> <workDir> [passes]
//   overhead_bench values <impl> <n> <boxKind> <workDir>
//   overhead_bench contains <impl> <n> <boxKind> <workDir>
//   overhead_bench put <impl> <n>
//   overhead_bench putall <impl> <n>
//   overhead_bench delete <impl> <n>
//   overhead_bench deleteall <impl> <n>
//   overhead_bench single <impl> <op> <n> <boxKind>
// with impl: facade | raw, boxKind: eager | lazy, op: get | set
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

/// How many times the get lane replays its whole sample inside one timed window. One by default:
/// the historical shape, and the one the README's per-get percentages describe.
///
/// Raising it is **not** a free noise reduction, so it stays opt-in. A single 100K eager pass runs
/// ~50 ms, which is close enough to process-startup and scheduling noise that a busy host swings
/// the reading from -6% to +27% run to run, and a wider window does clear that floor. But it also
/// changes the question: the façade allocates a `Some` per get where raw allocates nothing, so ten
/// replays turn 100K allocations into 1M and the lane starts charging the façade for young-gen GC
/// it never reached in one pass. Measured that way the eager lane reads +23% instead of ~+2%.
///
/// Both are real numbers for different questions ("one cold pass" vs "sustained reads"). Pass an
/// explicit count when you want the sustained one, and label it as such wherever it lands.
const defaultGetPasses = 1;

Future<void> main(List<String> args) async {
  switch (args) {
    case ['prep', final n, final workDir]:
      await runPrep(int.parse(n), workDir);
    case ['get', final impl, final n, final boxKind, final workDir]:
      await runGet(impl, int.parse(n), boxKind, workDir);
    case ['get', final impl, final n, final boxKind, final workDir, final passes]:
      await runGet(impl, int.parse(n), boxKind, workDir, passes: int.parse(passes));
    case ['values', final impl, final n, final boxKind, final workDir]:
      await runValues(impl, int.parse(n), boxKind, workDir);
    case ['contains', final impl, final n, final boxKind, final workDir]:
      await runContains(impl, int.parse(n), boxKind, workDir);
    case ['put', final impl, final n]:
      await runPut(impl, int.parse(n));
    case ['putall', final impl, final n]:
      await runPutAll(impl, int.parse(n));
    case ['putallby', final impl, final n]:
      await runPutAllBy(impl, int.parse(n));
    case ['delete', final impl, final n]:
      await runDelete(impl, int.parse(n), batched: false);
    case ['deleteall', final impl, final n]:
      await runDelete(impl, int.parse(n), batched: true);
    case ['single', final impl, final op, final n, final boxKind]:
      await runSingleValue(impl, op, int.parse(n), boxKind);
    default:
      throw ArgumentError.value(args.join(' '), 'args', 'unrecognised invocation');
  }
}

/// A fresh temp dir with hive pointed at it, for the lanes that must own their box (every write
/// lane mutates, so they cannot share the read lanes' prepped file).
Directory scratchBox(String suffix) {
  final dir = Directory.systemTemp.createTempSync('hbm_overhead_$suffix');
  Hive.init(dir.path);

  return dir;
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

Future<void> runGet(String impl, int n, String boxKind, String workDir, {int? passes}) async {
  Hive.init(workDir);
  final random = Random(getSampleSeed);
  final sampleSize = boxKind == 'lazy' ? min(n, maxLazyGetOps) : n;
  final sampleKeys = List.generate(sampleSize, (_) => random.nextInt(n), growable: false);
  final passCount = passes ?? defaultGetPasses;

  final stopwatch = Stopwatch();
  var checksum = 0;

  if (boxKind == 'eager' && impl == 'facade') {
    final box = await KeyedBox.open<String, int>(boxName).run();
    stopwatch.start();
    for (var pass = 0; pass < passCount; pass++) {
      for (final key in sampleKeys) {
        checksum += box.get(key).toNullable()!.length;
      }
    }
    stopwatch.stop();
  } else if (boxKind == 'eager') {
    final box = await Hive.openBox<String>(boxName);
    stopwatch.start();
    for (var pass = 0; pass < passCount; pass++) {
      for (final key in sampleKeys) {
        checksum += box.get(key)!.length;
      }
    }
    stopwatch.stop();
  } else if (impl == 'facade') {
    final box = LazyKeyedBox<String, int>(boxName);
    await box.ensureInitialised().run();
    stopwatch.start();
    for (var pass = 0; pass < passCount; pass++) {
      for (final key in sampleKeys) {
        checksum += (await box.get(key).run()).toNullable()!.length;
      }
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openLazyBox<String>(boxName);
    stopwatch.start();
    for (var pass = 0; pass < passCount; pass++) {
      for (final key in sampleKeys) {
        checksum += (await box.get(key))!.length;
      }
    }
    stopwatch.stop();
  }

  emit({
    'mode': 'get',
    'impl': impl,
    'n': n,
    'boxKind': boxKind,
    'passes': passCount,
    // Total timed ops, so per-op cost stays a plain division whatever the pass count.
    'ops': sampleSize * passCount,
    'micros': stopwatch.elapsedMicroseconds,
    'checksum': checksum,
  });
}

/// Full read-all pass. Eager `values` is a lazily-decoded `Iterable`, so it is consumed here rather
/// than merely obtained: the decode cost lands on iteration, not on the call. Lazy `values` fetches
/// every value from disk in parallel, so the raw baseline mirrors that shape (`keys.map(get).wait`)
/// instead of looping sequentially.
Future<void> runValues(String impl, int n, String boxKind, String workDir) async {
  Hive.init(workDir);

  final stopwatch = Stopwatch();
  var checksum = 0;

  if (boxKind == 'eager' && impl == 'facade') {
    final box = await KeyedBox.open<String, int>(boxName).run();
    stopwatch.start();
    for (final value in box.values) {
      checksum += value.length;
    }
    stopwatch.stop();
  } else if (boxKind == 'eager') {
    final box = await Hive.openBox<String>(boxName);
    stopwatch.start();
    for (final value in box.values) {
      checksum += value.length;
    }
    stopwatch.stop();
  } else if (impl == 'facade') {
    final box = LazyKeyedBox<String, int>(boxName);
    await box.ensureInitialised().run();
    stopwatch.start();
    final values = await box.values.run();
    stopwatch.stop();
    checksum = values.fold(0, (sum, value) => sum + value.length);
  } else {
    final box = await Hive.openLazyBox<String>(boxName);
    stopwatch.start();
    final storedValues = await box.keys.map(box.get).wait;
    stopwatch.stop();
    checksum = storedValues.fold(0, (sum, value) => sum + value!.length);
  }

  emit({
    'mode': 'values',
    'impl': impl,
    'n': n,
    'boxKind': boxKind,
    'ops': n,
    'micros': stopwatch.elapsedMicroseconds,
    'checksum': checksum,
  });
}

/// Key-presence checks: the cheapest op on the surface (one keystore lookup, no value decode and no
/// `Option`), so this is where a per-call wrapper frame shows up most starkly if it shows up at all.
Future<void> runContains(String impl, int n, String boxKind, String workDir) async {
  Hive.init(workDir);
  final random = Random(getSampleSeed);
  final sampleKeys = List.generate(n, (_) => random.nextInt(n), growable: false);

  final stopwatch = Stopwatch();
  var hits = 0;

  if (boxKind == 'eager' && impl == 'facade') {
    final box = await KeyedBox.open<String, int>(boxName).run();
    stopwatch.start();
    for (final key in sampleKeys) {
      if (box.contains(key)) hits++;
    }
    stopwatch.stop();
  } else if (boxKind == 'eager') {
    final box = await Hive.openBox<String>(boxName);
    stopwatch.start();
    for (final key in sampleKeys) {
      if (box.containsKey(key)) hits++;
    }
    stopwatch.stop();
  } else if (impl == 'facade') {
    // `contains` is a sync inspector on the lazy façade, so the box has to be open before it is
    // legal to call: that open stays outside the timed window, exactly like the get lane's.
    final box = LazyKeyedBox<String, int>(boxName);
    await box.ensureInitialised().run();
    stopwatch.start();
    for (final key in sampleKeys) {
      if (box.contains(key)) hits++;
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openLazyBox<String>(boxName);
    stopwatch.start();
    for (final key in sampleKeys) {
      if (box.containsKey(key)) hits++;
    }
    stopwatch.stop();
  }

  emit({
    'mode': 'contains',
    'impl': impl,
    'n': n,
    'boxKind': boxKind,
    'ops': n,
    'micros': stopwatch.elapsedMicroseconds,
    'hits': hits,
  });
}

/// One batched write of [n] entries. The façade encodes and gates every key up front, before the
/// task exists, so this lane charges it for a full extra pass over the batch that raw never makes.
Future<void> runPutAll(String impl, int n) async {
  final dir = scratchBox('putall_');
  // Built outside the timed window: the batch map is the input, not part of the operation.
  final batch = {for (var i = 0; i < n; i++) i: 'v'};

  final stopwatch = Stopwatch();
  if (impl == 'facade') {
    final box = await KeyedBox.open<String, int>(boxName).run();
    stopwatch.start();
    await box.putAll(batch).run();
    stopwatch.stop();
    await box.close().run();
  } else {
    final box = await Hive.openBox<String>(boxName);
    stopwatch.start();
    await box.putAll(batch);
    stopwatch.stop();
    await box.close();
  }

  emit({'mode': 'putall', 'impl': impl, 'n': n, 'ops': n, 'micros': stopwatch.elapsedMicroseconds});
  dir.deleteSync(recursive: true);
}

/// The `putAllBy` lane: from a flat list of values to written, caller prep **included**.
///
/// Deliberately unlike [runPutAll], which treats the batch map as given input because it measures
/// the write. Here building that map *is* what is under test, since removing it is the whole point
/// of `putAllBy`. Both impls start from the same flat list and pay for whatever they need on the
/// way to hive.
///
///   map     `Map.fromIterables(values, values)` then `putAll`: what a consumer writes without it.
///   facade  `putAllBy(values, key: ...)`.
///
/// Keys are the values themselves (`KeyedBox<String, String>`), so the extractor is identity and
/// costs the same on both sides. Anything expensive there would add a constant to both impls and
/// bury the difference being measured.
Future<void> runPutAllBy(String impl, int n) async {
  final dir = scratchBox('putallby_');
  // Built outside the window: the *values* are this lane's input. Turning them into a batch is not.
  final values = [for (var i = 0; i < n; i++) 'v$i'];

  final stopwatch = Stopwatch();
  final box = await KeyedBox.open<String, String>(boxName).run();
  if (impl == 'facade') {
    stopwatch.start();
    await box.putAllBy(values, key: (value) => value).run();
    stopwatch.stop();
  } else {
    stopwatch.start();
    await box.putAll(Map.fromIterables(values, values)).run();
    stopwatch.stop();
  }
  await box.close().run();

  emit({
    'mode': 'putallby',
    'impl': impl,
    'n': n,
    'ops': n,
    'micros': stopwatch.elapsedMicroseconds,
  });
  dir.deleteSync(recursive: true);
}

/// Deletes, either [n] sequential single calls or one batch. The box is seeded outside the timed
/// window, and deletes need their own box because they consume it.
Future<void> runDelete(String impl, int n, {required bool batched}) async {
  final dir = scratchBox(batched ? 'deleteall_' : 'delete_');
  final keys = List.generate(n, (index) => index, growable: false);

  final stopwatch = Stopwatch();
  if (impl == 'facade') {
    final box = await KeyedBox.open<String, int>(boxName).run();
    await box.putAll({for (final key in keys) key: 'v'}).run();
    stopwatch.start();
    if (batched) {
      await box.deleteAll(keys).run();
    } else {
      for (final key in keys) {
        await box.delete(key).run();
      }
    }
    stopwatch.stop();
    await box.close().run();
  } else {
    final box = await Hive.openBox<String>(boxName);
    await box.putAll({for (final key in keys) key: 'v'});
    stopwatch.start();
    if (batched) {
      await box.deleteAll(keys);
    } else {
      for (final key in keys) {
        await box.delete(key);
      }
    }
    stopwatch.stop();
    await box.close();
  }

  emit({
    'mode': batched ? 'deleteall' : 'delete',
    'impl': impl,
    'n': n,
    'ops': n,
    'micros': stopwatch.elapsedMicroseconds,
  });
  dir.deleteSync(recursive: true);
}

/// The single-value façades against their raw shape: one fixed slot key, no key argument on the
/// surface. Slot `0` is the compatibility invariant the façade stores under, so the raw baseline
/// addresses the same slot.
Future<void> runSingleValue(String impl, String op, int n, String boxKind) async {
  const slotKey = 0;
  final dir = scratchBox('single_');

  final stopwatch = Stopwatch();
  var checksum = 0;

  if (boxKind == 'eager' && impl == 'facade') {
    final box = await SingleValueBox.open<String>(boxName).run();
    await box.set('v').run();
    stopwatch.start();
    for (var i = 0; i < n; i++) {
      if (op == 'get') {
        checksum += box.get().toNullable()!.length;
      } else {
        await box.set('v').run();
      }
    }
    stopwatch.stop();
  } else if (boxKind == 'eager') {
    final box = await Hive.openBox<String>(boxName);
    await box.put(slotKey, 'v');
    stopwatch.start();
    for (var i = 0; i < n; i++) {
      if (op == 'get') {
        checksum += box.get(slotKey)!.length;
      } else {
        await box.put(slotKey, 'v');
      }
    }
    stopwatch.stop();
  } else if (impl == 'facade') {
    final box = LazySingleValueBox<String>(boxName);
    await box.set('v').run();
    stopwatch.start();
    for (var i = 0; i < n; i++) {
      if (op == 'get') {
        checksum += (await box.get().run()).toNullable()!.length;
      } else {
        await box.set('v').run();
      }
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openLazyBox<String>(boxName);
    await box.put(slotKey, 'v');
    stopwatch.start();
    for (var i = 0; i < n; i++) {
      if (op == 'get') {
        checksum += (await box.get(slotKey))!.length;
      } else {
        await box.put(slotKey, 'v');
      }
    }
    stopwatch.stop();
  }

  await Hive.close();
  emit({
    'mode': 'single-$op',
    'impl': impl,
    'n': n,
    'boxKind': boxKind,
    'ops': n,
    'micros': stopwatch.elapsedMicroseconds,
    'checksum': checksum,
  });
  dir.deleteSync(recursive: true);
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
