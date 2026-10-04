// dart2wasm keeps 64-bit ints like the VM, so it can hold an int hive would read back as a neighbour.
// dart2js can't, since every int there is already a double.
@TestOn('dart2wasm')
@Tags(['browser'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  feature('MapBox inner int keys on dart2wasm', () {
    scenario("a write with an int key hive can't store exactly fails at the call", () {
      // Lazy, so the box never opens and the test needs no Hive.init.
      final box = LazyMapBox<int, String, int>(uniqueBoxName('maps_imprecise'));

      check(() => box.put(1, {ProbeKeyLimits.firstWebImpreciseInt: 'a'})).throws<ArgumentError>();
    });
  });
}
