// Pins hive_ce 2.19.3's lifecycle semantics (probe P5): idempotent double open, wrong-kind reopen
// throwing while open, and isBoxOpen tracking. The 1.0 lifecycle core leans on these, and the tier-3
// rule (never duplicate a precondition the engine already throws for) requires the engine to keep
// erroring where it errors today.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:io';

import 'package:checks/checks.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hbm_pins_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('hive_ce box lifecycle semantics', () {
    scenario('double openBox of the same name returns the identical instance', () async {
      final first = await Hive.openBox<String>('lifecycle');
      final second = await Hive.openBox<String>('lifecycle');

      check(identical(first, second)).isTrue();
    });

    scenario('opening the same name as a different box kind throws while open', () async {
      await Hive.openBox<String>('lifecycle');

      await check(Hive.openLazyBox<String>('lifecycle')).throws<HiveError>();
    });

    scenario('isBoxOpen tracks open and close; a closed name reopens fine', () async {
      final box = await Hive.openBox<String>('lifecycle');
      check(Hive.isBoxOpen('lifecycle')).isTrue();

      await box.close();
      check(Hive.isBoxOpen('lifecycle')).isFalse();

      final reopened = await Hive.openBox<String>('lifecycle');
      check(reopened.isOpen).isTrue();
    });
  });
}
