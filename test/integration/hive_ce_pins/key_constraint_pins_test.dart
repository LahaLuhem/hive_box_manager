// Pins hive_ce's key handling. Its only key check is an assert, so in release out-of-range ints wrap
// and oversized String keys corrupt the box file. That's why the write path has its own gate.
// The release verdicts carry hive's List<dynamic> keystore shapes, hence the lifted DCM ban.
// ignore_for_file: avoid-dynamic
@TestOn('vm')
@Tags(['integration'])
library;

import 'package:checks/checks.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/support.dart';

void main() {
  useTempHive('hbm_pins_');

  feature('hive_ce key constraints on the write path', () {
    scenarioOutline<Object>(
      'out-of-range keys are rejected at put while asserts are on (Frame.assertKey)',
      examples: {
        'int -1': -1,
        'int one past the u32 ceiling': HiveKeyLimits.maxIntKey + 1,
        'int past double precision (2^53 + 1)': ProbeKeyLimits.firstWebImpreciseInt,
        'String one byte over the limit': 'b' * (HiveKeyLimits.maxStringKeyBytes + 1),
        'String far over the limit': 'c' * ProbeKeyLimits.farOversizedKeyLength,
      },
      outline: (writeKey) async {
        final box = await Hive.openBox<String>('keys');

        // Future.sync folds the guard's synchronous throw into the checked future.
        await check(Future.sync(() => box.put(writeKey, 'stored-value'))).throws<HiveError>();
      },
    );

    scenario('the u32-max int key round-trips exactly', () async {
      var box = await Hive.openBox<String>('keys');
      await box.put(HiveKeyLimits.maxIntKey, 'stored-value');
      await box.close();

      box = await Hive.openBox<String>('keys');
      check(box.get(HiveKeyLimits.maxIntKey)).equals('stored-value');
    });

    scenarioOutline<String>(
      'in-range String keys round-trip, including non-ASCII and separators',
      examples: {
        'exactly the byte-length limit (ASCII)': 'a' * HiveKeyLimits.maxStringKeyBytes,
        'non-ASCII (héllo)': 'héllo',
        'composite-looking separator (12:34)': '12:34',
      },
      outline: (key) async {
        var box = await Hive.openBox<String>('keys');
        await box.put(key, 'stored-value');
        await box.close();

        box = await Hive.openBox<String>('keys');
        check(box.get(key)).equals('stored-value');
      },
    );

    scenario('int and String keys coexist in one box', () async {
      var box = await Hive.openBox<String>('keys');
      await box.put(1, 'int-keyed');
      await box.put('one', 'string-keyed');
      await box.close();

      box = await Hive.openBox<String>('keys');
      check(box.get(1)).equals('int-keyed');
      check(box.get('one')).equals('string-keyed');
    });
  });

  feature('hive_ce key handling with asserts stripped (release truth, via subprocess)', () {
    late Map<String, Object?> verdicts;

    setUpAll(() async => verdicts = await runReleaseModeProbe());

    scenarioOutline<({String label, int storedKey})>(
      'out-of-range int keys wrap silently into u32 and become unreachable',
      examples: {
        'int -1 wraps to u32 max': (label: 'minus1', storedKey: HiveKeyLimits.maxIntKey),
        'int 2^32 wraps to 0': (label: 'pow32', storedKey: 0),
        'int 2^53 + 1 wraps to 1': (label: 'pow53plus1', storedKey: 1),
      },
      outline: (example) {
        check(verdicts['${example.label}StoredKeys'])
            .isA<List<dynamic>>()
            .deepEquals([example.storedKey]);
        check(verdicts['${example.label}GetOriginalIsNull']).equals(true);
        check(verdicts['${example.label}GetStoredValue']).equals('stored-value');
      },
    );

    scenarioOutline<String>(
      'String keys of 256+ bytes corrupt the whole box file (unreadable on reopen)',
      examples: {'one byte over': 'oversizedByOne', 'far over': 'oversizedFar'},
      outline: (label) {
        check(verdicts['${label}ReopenOutcome']).isA<String>().startsWith('threw ');
      },
    );
  });
}
