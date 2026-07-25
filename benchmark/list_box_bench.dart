// List-box lane: `ListBox` against the two things a consumer would hand-write instead.
// One measurement per process invocation; emits one JSON line. Drive via list_box_driver.sh.
//
// Three impls, because "vs raw hive_ce" is not one question here. Raw hive_ce has no list-valued
// box, so the baseline is code a consumer writes, and there are two versions of that code:
//
//   naive    `box.get(k) as List<T>` and `box.put(k, list)`. What you write first.
//   correct  the same with `.cast<T>()` at the read boundary and a defensive `List.from` at the
//            write boundary. What a consumer writes after being bitten. This is the honest
//            wrapper-tax denominator.
//   facade   `ListBox`.
//
// So: naive-vs-facade prices safety, correct-vs-facade prices the wrapper. Reporting only one of
// them would answer the wrong question.
//
// Second axis: the **element type**, because whether the naive baseline is broken at all depends on
// it. Probed against hive_ce 2.19.3:
//
//   str  a `List<String>` reads back from disk as `List<String>`. The engine specialises lists of
//        primitives, so the naive cast survives a restart and hand-rolling is genuinely fine.
//   obj  a `List<Person>` (adapter-registered custom type) reads back as `List<dynamic>`, so the
//        naive cast throws TypeError on the first post-restart read. This is upstream #150, pinned
//        in test/integration/hive_ce_pins/collection_disk_truth_test.dart, and it is the reason
//        `ListBox` exists.
//
// The read lanes record that throw as the result rather than dying on it: "this baseline cannot read
// its own data back" is the measurement, and it only lands on one of the two element types.
//
// Third axis: **elements per key**, not entries per box, because that is what every cost here
// scales with: the write path materialises a private copy (O(n) per put), `add` / `remove` are
// read-modify-writes (O(n) in the stored list), and the read path's cast view is O(1) to obtain and
// O(n) across iteration. Box size is held constant.
//
// Usage: list_box_bench <mode> <impl> <elem> <keys> <listLen> [workDir]
//   modes: prep | put | putall | get | add | remove | open
//   impl: naive | correct | facade
//   elem: str | obj
import 'dart:convert';
import 'dart:io';

import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:meta/meta.dart';

const boxName = 'ibench';

/// A custom element type, so one axis of this lane exercises the reification trap that only fires
/// for adapter-registered types. Mirrors the pin suite's fixture (hand-written, no codegen).
@immutable
class Person {
  final String name;
  final int age;

  const Person(this.name, this.age);

  @override
  bool operator ==(Object other) => other is Person && other.name == name && other.age == age;

  @override
  int get hashCode => Object.hash(name, age);
}

class PersonAdapter extends TypeAdapter<Person> {
  @override
  final typeId = 1;

  @override
  Person read(BinaryReader reader) => Person(reader.readString(), reader.readInt());

  @override
  void write(BinaryWriter writer, Person obj) => writer
    ..writeString(obj.name)
    ..writeInt(obj.age);
}

String stringElementAt(int index) => 'e$index';

Person personElementAt(int index) => Person('e$index', index);

int weighString(String element) => element.length;

int weighPerson(Person element) => element.name.length;

/// Everything a lane needs about its element type, so `ListBox<T, K>` and the raw casts can stay
/// statically typed while the element type varies per invocation.
///
/// [weigh] exists to force iteration: without touching each element the read lanes would measure
/// obtaining the cast view (O(1)) instead of walking it (O(n)), which is the cost under test.
@immutable
class ElementSpec<T extends Object> {
  final T Function(int index) at;
  final int Function(T element) weigh;

  const ElementSpec({required this.at, required this.weigh});

  List<T> list(int listLen) => List<T>.generate(listLen, at, growable: false);

  /// Mid-list, so the remove lane's `indexOf` walks half of it on average.
  T removeTarget(int listLen) => at(listLen ~/ 2);
}

const stringSpec = ElementSpec<String>(at: stringElementAt, weigh: weighString);
const personSpec = ElementSpec<Person>(at: personElementAt, weigh: weighPerson);

/// One lane's outcome. `failure` is non-null only where a baseline could not complete, which for the
/// naive impl on custom types is the finding rather than an error. `fileBytes` is prep's alone.
typedef LaneResult = ({int micros, int checksum, int rssDelta, int? fileBytes, String? failure});

void initHive(String path, String elem) {
  Hive.init(path);
  if (elem == 'obj' && !Hive.isAdapterRegistered(PersonAdapter().typeId)) {
    Hive.registerAdapter(PersonAdapter());
  }
}

/// A fresh temp dir with hive pointed at it, for the lanes that mutate and so cannot share a box.
Directory scratchBox(String suffix, String elem) {
  final dir = Directory.systemTemp.createTempSync('hbm_list_box_$suffix');
  initHive(dir.path, elem);

  return dir;
}

void emit(Map<String, Object?> record) => stdout.writeln(jsonEncode(record));

Future<void> main(List<String> args) async {
  final mode = args.first;
  final impl = args[1];
  final elem = args[2];
  final keys = int.parse(args[3]);
  final listLen = int.parse(args[4]);
  final workDir = args.length > 5 ? args[5] : '';

  // Prep is impl-agnostic by design (one file serves all three), so it alone takes any impl token.
  if (mode != 'prep' && impl != 'naive' && impl != 'correct' && impl != 'facade') {
    throw ArgumentError('unknown impl: $impl');
  }
  if (elem != 'str' && elem != 'obj') throw ArgumentError('unknown elem: $elem');

  // Dispatched once, here: every lane body below is generic in the element type, so the two axes
  // differ only in which spec they are handed.
  final result = switch ((mode, elem)) {
    ('prep', 'obj') => await runPrep(personSpec, keys, listLen, workDir, elem),
    ('prep', _) => await runPrep(stringSpec, keys, listLen, workDir, elem),
    ('put' || 'putall', 'obj') => await runPut(
      personSpec,
      impl,
      elem,
      keys,
      listLen,
      batched: mode == 'putall',
    ),
    ('put' || 'putall', _) => await runPut(
      stringSpec,
      impl,
      elem,
      keys,
      listLen,
      batched: mode == 'putall',
    ),
    ('get', 'obj') => await runGet(personSpec, impl, elem, keys, workDir),
    ('get', _) => await runGet(stringSpec, impl, elem, keys, workDir),
    ('add', 'obj') => await runAdd(personSpec, impl, elem, keys, listLen),
    ('add', _) => await runAdd(stringSpec, impl, elem, keys, listLen),
    ('remove', 'obj') => await runRemove(personSpec, impl, elem, keys, listLen),
    ('remove', _) => await runRemove(stringSpec, impl, elem, keys, listLen),
    ('open', 'obj') => await runOpen(personSpec, impl, elem, keys, workDir),
    ('open', _) => await runOpen(stringSpec, impl, elem, keys, workDir),
    _ => throw ArgumentError('unknown mode: $mode'),
  };

  emit({
    'mode': mode,
    'impl': mode == 'prep' ? 'shared' : impl,
    'elem': elem,
    'keys': keys,
    'listLen': listLen,
    'ops': keys,
    'elements': keys * listLen,
    'micros': result.micros,
    'rssDeltaBytes': result.rssDelta,
    'checksum': result.checksum,
    'fileBytes': result.fileBytes,
    'failure': result.failure,
  });
}

/// Seeds the shared box the read lanes open. Written raw and untyped, which is byte-identical to what
/// the façade writes (its value codec is the identity on the way in), so one file serves all three
/// impls.
Future<LaneResult> runPrep<T extends Object>(
  ElementSpec<T> spec,
  int keys,
  int listLen,
  String workDir,
  String elem,
) async {
  initHive(workDir, elem);
  final box = await Hive.openBox<Object?>(boxName);
  await box.putAll({for (var key = 0; key < keys; key++) key: spec.list(listLen)});
  await box.flush();

  final fileBytes = File('$workDir/$boxName.hive').lengthSync();
  await Hive.close();

  return (micros: 0, checksum: 0, rssDelta: 0, fileBytes: fileBytes, failure: null);
}

/// Writes, either [keys] sequential puts or one batch. RSS spans the timed window: the façade
/// materialises a private fixed-length copy per list, and `putAll` builds a whole second map of them
/// before anything reaches hive, so this is where that shows up if it shows up.
Future<LaneResult> runPut<T extends Object>(
  ElementSpec<T> spec,
  String impl,
  String elem,
  int keys,
  int listLen, {
  required bool batched,
}) async {
  final dir = scratchBox(batched ? 'putall_' : 'put_', elem);
  // Built outside the timed window: these are the operation's input, not part of it.
  final values = spec.list(listLen);
  final batch = {for (var key = 0; key < keys; key++) key: values};

  final stopwatch = Stopwatch();
  final rssBefore = ProcessInfo.currentRss;

  if (impl == 'facade') {
    final box = await ListBox.open<T, int>(boxName).run();
    stopwatch.start();
    if (batched) {
      await box.putAll(batch).run();
    } else {
      for (var key = 0; key < keys; key++) {
        await box.put(key, values).run();
      }
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openBox<Object?>(boxName);
    stopwatch.start();
    if (batched) {
      // The defensive copy is the whole difference between the two baselines on the write path.
      await box.putAll(
        impl == 'correct'
            ? batch.map((key, list) => MapEntry(key, List<T>.from(list, growable: false)))
            : batch,
      );
    } else {
      for (var key = 0; key < keys; key++) {
        await box.put(key, impl == 'correct' ? List<T>.from(values, growable: false) : values);
      }
    }
    stopwatch.stop();
  }

  final rssDelta = ProcessInfo.currentRss - rssBefore;
  await Hive.close();
  dir.deleteSync(recursive: true);

  return (
    micros: stopwatch.elapsedMicroseconds,
    checksum: 0,
    rssDelta: rssDelta,
    fileBytes: null,
    failure: null,
  );
}

/// Reads every key and **fully iterates** each list. Iteration is the point: the façade hands back an
/// unmodifiable cast view, which costs nothing to obtain and one type check per element to walk, so a
/// lane that only called `get` would measure the cheap half and miss the cost entirely.
///
/// On the `obj` axis the naive impl throws here rather than returning a number. That is the finding:
/// this box was written by a previous process, which is exactly the condition `as List<T>` cannot
/// survive for an adapter-registered type.
Future<LaneResult> runGet<T extends Object>(
  ElementSpec<T> spec,
  String impl,
  String elem,
  int keys,
  String workDir,
) async {
  initHive(workDir, elem);

  final stopwatch = Stopwatch();
  final rssBefore = ProcessInfo.currentRss;
  var checksum = 0;
  String? failure;

  if (impl == 'facade') {
    final box = await ListBox.open<T, int>(boxName).run();
    stopwatch.start();
    for (var key = 0; key < keys; key++) {
      for (final element in box.getOr(key)) {
        checksum += spec.weigh(element);
      }
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openBox<Object?>(boxName);
    stopwatch.start();
    try {
      for (var key = 0; key < keys; key++) {
        final stored = impl == 'correct'
            ? (box.get(key)! as List<Object?>).cast<T>()
            : box.get(key)! as List<T>;
        for (final element in stored) {
          checksum += spec.weigh(element);
        }
      }
      // The Error is the subject here: this lane exists to record that the naive baseline cannot read
      // its own data back, so letting it kill the process would throw the measurement away.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      failure = 'TypeError: $error';
    }
    stopwatch.stop();
  }

  final rssDelta = ProcessInfo.currentRss - rssBefore;
  await Hive.close();

  return (
    micros: stopwatch.elapsedMicroseconds,
    checksum: checksum,
    rssDelta: rssDelta,
    fileBytes: null,
    failure: failure,
  );
}

/// Appends one element to every key: a read-modify-write, O(listLen) per op on every impl. The box is
/// seeded in-process, so the naive impl's read still works even on the `obj` axis (hive's write cache
/// hands back the instance it just stored, pinned) and the lane measures all three.
Future<LaneResult> runAdd<T extends Object>(
  ElementSpec<T> spec,
  String impl,
  String elem,
  int keys,
  int listLen,
) async {
  final dir = scratchBox('add_', elem);
  final appended = spec.at(listLen);
  // A distinct list per key, in every impl. Sharing one instance across keys (which raw hive_ce
  // happily does) would leave the raw baselines holding a single list where the façade's putAll has
  // materialised one per key, and the RSS column below would report that seeding difference as a
  // wrapper cost.
  final seed = {for (var key = 0; key < keys; key++) key: spec.list(listLen)};

  final stopwatch = Stopwatch();
  late final int rssBefore;

  if (impl == 'facade') {
    final box = await ListBox.open<T, int>(boxName).run();
    await box.putAll(seed).run();
    // Sampled after seeding, so the window covers the operation under test and not the setup.
    rssBefore = ProcessInfo.currentRss;
    stopwatch.start();
    for (var key = 0; key < keys; key++) {
      await box.add(key, appended).run();
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openBox<Object?>(boxName);
    await box.putAll(seed);
    rssBefore = ProcessInfo.currentRss;
    stopwatch.start();
    for (var key = 0; key < keys; key++) {
      final stored = impl == 'correct'
          ? (box.get(key)! as List<Object?>).cast<T>()
          : box.get(key)! as List<T>;
      await box.put(key, <T>[...stored, appended]);
    }
    stopwatch.stop();
  }

  final rssDelta = ProcessInfo.currentRss - rssBefore;
  await Hive.close();
  dir.deleteSync(recursive: true);

  return (
    micros: stopwatch.elapsedMicroseconds,
    checksum: 0,
    rssDelta: rssDelta,
    fileBytes: null,
    failure: null,
  );
}

/// Removes one mid-list element from every key. Distinct from [runAdd] because the façade implements
/// it directly (`indexOf`, then a copy skipping that index) rather than through the update path, so it
/// walks the list twice where `add` walks it once.
Future<LaneResult> runRemove<T extends Object>(
  ElementSpec<T> spec,
  String impl,
  String elem,
  int keys,
  int listLen,
) async {
  final dir = scratchBox('remove_', elem);
  // Distinct per key, for the same reason as the add lane.
  final seed = {for (var key = 0; key < keys; key++) key: spec.list(listLen)};
  final target = spec.removeTarget(listLen);

  final stopwatch = Stopwatch();

  if (impl == 'facade') {
    final box = await ListBox.open<T, int>(boxName).run();
    await box.putAll(seed).run();
    stopwatch.start();
    for (var key = 0; key < keys; key++) {
      await box.remove(key, target).run();
    }
    stopwatch.stop();
  } else {
    final box = await Hive.openBox<Object?>(boxName);
    await box.putAll(seed);
    stopwatch.start();
    for (var key = 0; key < keys; key++) {
      final stored = impl == 'correct'
          ? (box.get(key)! as List<Object?>).cast<T>()
          : box.get(key)! as List<T>;
      final index = stored.indexOf(target);
      if (index >= 0) {
        await box.put(key, <T>[...stored.take(index), ...stored.skip(index + 1)]);
      }
    }
    stopwatch.stop();
  }

  await Hive.close();
  dir.deleteSync(recursive: true);

  return (
    micros: stopwatch.elapsedMicroseconds,
    checksum: 0,
    rssDelta: 0,
    fileBytes: null,
    failure: null,
  );
}

/// Open cost and the RSS the eager value cache costs, per impl. The façade wraps the same hive box, so
/// this lane exists to confirm it adds nothing rather than to find something.
Future<LaneResult> runOpen<T extends Object>(
  ElementSpec<T> spec,
  String impl,
  String elem,
  int keys,
  String workDir,
) async {
  initHive(workDir, elem);

  final rssBefore = ProcessInfo.currentRss;
  final stopwatch = Stopwatch()..start();
  final int length;
  if (impl == 'facade') {
    final box = await ListBox.open<T, int>(boxName).run();
    stopwatch.stop();
    length = box.length;
  } else {
    final box = await Hive.openBox<Object?>(boxName);
    stopwatch.stop();
    length = box.length;
  }
  final rssDelta = ProcessInfo.currentRss - rssBefore;

  await Hive.close();

  return (
    micros: stopwatch.elapsedMicroseconds,
    checksum: length,
    rssDelta: rssDelta,
    fileBytes: null,
    failure: null,
  );
}
