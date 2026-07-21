// Not a test: the pin suites run this in a subprocess so it executes WITHOUT asserts, the way a
// release build does. hive_ce's write-path key guard (Frame.assertKey) and the typed-collection-box
// open guard (typedMapOrIterableCheck) are assert-gated: active under `dart test` and in debug builds,
// stripped in release, where the silent behaviours live. This probe reports what release-mode hive_ce
// actually does, one flat JSON map on stdout; the pin suites assert its verdicts via `runReleaseModeProbe`.
//
// Deliberately NOT named *_test.dart: there are no test() calls, the runner must never load it,
// and it lives beside the pins it serves.
// ignore_for_file: prefer-correct-test-file-name
import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import 'person.dart';
import 'probe_key_limits.dart';

/// Stable labels for caught errors: `runtimeType` names are VM-internal (`_TypeError`), so classify
/// by type test instead.
String throwLabel(Object error) => switch (error) {
  TypeError() => 'threw TypeError',
  HiveError() => 'threw HiveError',
  _ => 'threw ${error.runtimeType}',
};

Future<void> main(List<String> args) async {
  final workDir = args.first;
  final verdicts = <String, Object?>{
    ...await probeIntWrap('minus1', -1, workDir),
    ...await probeIntWrap('pow32', HiveKeyLimits.maxIntKey + 1, workDir),
    ...await probeIntWrap('pow53plus1', ProbeKeyLimits.firstWebImpreciseInt, workDir),
    ...await probeOversizedString(
      'oversizedByOne',
      'b' * (HiveKeyLimits.maxStringKeyBytes + 1),
      workDir,
    ),
    ...await probeOversizedString(
      'oversizedFar',
      'c' * ProbeKeyLimits.farOversizedKeyLength,
      workDir,
    ),
    ...await probeTypedBox(workDir),
  };

  stdout.writeln(jsonEncode(verdicts));
}

/// Writes under an out-of-range int key, reopens from disk, and reports the stored key plus reachability
/// of the original.
Future<Map<String, Object?>> probeIntWrap(String label, int writeKey, String workDir) async {
  final dir = Directory('$workDir/$label')..createSync(recursive: true);
  Hive.init(dir.path);
  var box = await Hive.openBox<String>('probe');
  await box.put(writeKey, 'stored-value');
  await box.close();

  box = await Hive.openBox<String>('probe');
  final storedKeys = box.keys.toList();
  final verdict = <String, Object?>{
    '${label}StoredKeys': storedKeys,
    '${label}GetOriginalIsNull': box.get(writeKey) == null,
    '${label}GetStoredValue': storedKeys.isEmpty ? null : box.get(storedKeys.first),
  };
  await box.close();

  return verdict;
}

/// Writes under an oversized String key (accepted without asserts), then reports whether the box file
/// survives a reopen.
Future<Map<String, Object?>> probeOversizedString(
  String label,
  String writeKey,
  String workDir,
) async {
  final dir = Directory('$workDir/$label')..createSync(recursive: true);
  Hive.init(dir.path);
  final box = await Hive.openBox<String>('probe');
  await box.put(writeKey, 'stored-value');
  await box.close();

  try {
    final reopened = await Hive.openBox<String>('probe');
    final keyCount = reopened.length;
    await reopened.close();

    return {'${label}ReopenOutcome': 'opened with $keyCount keys'};
  } on Object catch (error) {
    return {'${label}ReopenOutcome': 'threw ${error.runtimeType}'};
  }
}

/// Round-trips a `Box<List<Person>>` (the upstream-#150 shape): without asserts the open succeeds
/// and only the first post-reopen get blows up.
Future<Map<String, Object?>> probeTypedBox(String workDir) async {
  final dir = Directory('$workDir/typed')..createSync(recursive: true);
  Hive
    ..init(dir.path)
    ..registerAdapter(PersonAdapter(), override: true);

  var openedFine = false;
  Object? eagerOutcome;
  Object? lazyOutcome;
  try {
    final box = await Hive.openBox<List<Person>>('probe');
    await box.put('k', [const Person('alice', 30)]);
    await box.close();

    final reopened = await Hive.openBox<List<Person>>('probe');
    openedFine = true;
    try {
      eagerOutcome = 'value ${reopened.get('k')}';
    } on Object catch (error) {
      eagerOutcome = throwLabel(error);
    }
    await reopened.close();

    final lazyBox = await Hive.openLazyBox<List<Person>>('probe');
    try {
      lazyOutcome = 'value ${await lazyBox.get('k')}';
    } on Object catch (error) {
      lazyOutcome = throwLabel(error);
    }
    await lazyBox.close();
  } on Object catch (error) {
    eagerOutcome ??= 'setup threw ${error.runtimeType}';
  }

  return {
    'typedBoxOpenedFine': openedFine,
    'typedBoxEagerGet': eagerOutcome,
    'typedBoxLazyGet': lazyOutcome,
  };
}
