// Pins hive_ce 2.19.3 serving `keys` and `values` in the same order. The eager read-all finds a
// failed value's key by position, because a lookup per value costs more than the lane allows.
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
    tempDir = Directory.systemTemp.createTempSync('hbm_order_pins_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  feature('hive_ce keys and values iterate in step', () {
    scenario('an eager box pairs them by position, in key order', () async {
      final box = await Hive.openBox<Object?>('ordered');
      // Written out of order, and with a gap, so insertion order cannot be what lines them up.
      await box.putAll({5: 'five', 1: 'one', 9: 'nine', 3: 'three'});

      check(box.keys.toList()).deepEquals([1, 3, 5, 9]);
      check(box.values.toList()).deepEquals(['one', 'three', 'five', 'nine']);
    });

    scenario('the pairing survives a delete and a reopen', () async {
      final box = await Hive.openBox<Object?>('ordered');
      await box.putAll({5: 'five', 1: 'one', 9: 'nine', 3: 'three'});
      await box.delete(5);
      await Hive.close();

      final reopened = await Hive.openBox<Object?>('ordered');

      check(reopened.keys.toList()).deepEquals([1, 3, 9]);
      check(reopened.values.toList()).deepEquals(['one', 'three', 'nine']);
    });

    scenario('String keys pair the same way', () async {
      final box = await Hive.openBox<Object?>('strings');
      await box.putAll({'c': 3, 'a': 1, 'b': 2});

      check(box.keys.toList()).deepEquals(['a', 'b', 'c']);
      check(box.values.toList()).deepEquals([1, 2, 3]);
    });
  });
}
