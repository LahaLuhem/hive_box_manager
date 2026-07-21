/// Runs `release_mode_probe.dart` in a subprocess with asserts off (matching a
/// release build) so the pin suites can assert release-mode engine truth that
/// `dart test` (asserts on) cannot observe in-process.
library;

import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';

/// Launches the probe via `dart run` and returns its flat verdict map.
///
/// Relies on the test runner's working directory being the package root,
/// which `dart test` guarantees.
Future<Map<String, Object?>> runReleaseModeProbe(Directory workDir) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'run',
    'test/support/release_mode_probe.dart',
    workDir.path,
  ]);
  check(result.exitCode, because: 'probe stderr: ${result.stderr}').equals(0);

  // The verdict map is the last stdout line, tolerating any tool preamble.
  final lines = (result.stdout as String).trim().split('\n');

  return (jsonDecode(lines.last) as Map<String, dynamic>).cast<String, Object?>();
}
