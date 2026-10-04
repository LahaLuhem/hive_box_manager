// Pins hive_ce's lifecycle semantics. The package skips its own checks where hive already throws, so
// hive has to keep throwing where it does today.
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:checks/checks.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/support.dart';

void main() {
  useTempHive('hbm_pins_');

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

    scenario('isBoxOpen tracks open and close, and a closed name reopens fine', () async {
      final box = await Hive.openBox<String>('lifecycle');
      check(Hive.isBoxOpen('lifecycle')).isTrue();

      await box.close();
      check(Hive.isBoxOpen('lifecycle')).isFalse();

      final reopened = await Hive.openBox<String>('lifecycle');
      check(reopened.isOpen).isTrue();
    });
  });
}
