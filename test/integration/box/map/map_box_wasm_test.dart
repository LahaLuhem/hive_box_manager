// dart2wasm keeps 64-bit ints like the VM, so it can hold an int hive would read back as a neighbour.
// dart2js can't, since every int there is already a double.
@TestOn('dart2wasm')
@Tags(['browser'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../../support/support.dart';

void main() {
  const imprecise = ProbeKeyLimits.firstWebImpreciseInt;

  // hive_ce's web backend ignores the path, since storage is IndexedDB.
  setUpAll(() => Hive.init('hive_web_wasm'));

  feature('inner int keys on dart2wasm', () {
    scenario("hive reads 2 keys a 64-bit float can't tell apart back as one entry", () async {
      final boxName = uniqueBoxName('int_keys');
      final neighbour = imprecise.toDouble().toInt();
      var box = await Hive.openBox<Object>(boxName);
      await box.put('map', {neighbour: 'first', imprecise: 'second'});
      await box.close();

      box = await Hive.openBox<Object>(boxName);

      check((box.get('map')! as Map<Object?, Object?>).keys).deepEquals([neighbour]);

      await box.deleteFromDisk();
    });

    scenario("MapBox refuses a write with an int key hive can't store exactly, at the call", () {
      final box = LazyMapBox<int, String, int>(uniqueBoxName('maps_imprecise'));

      check(() => box.put(1, {imprecise: 'a'})).throws<ArgumentError>();
    });
  });
}
