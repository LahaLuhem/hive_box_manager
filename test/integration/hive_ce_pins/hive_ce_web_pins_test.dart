// Pins the web platform for the 1.0 key/codec design (probe P2): packing arithmetic is exact under
// dart2js AND dart2wasm number semantics, and hive_ce's IndexedDB backend serves the same post-reopen
// collection shapes as the VM binary format. Per the 2026-07-21 ratification rider these reads
// happen after close + reopen, so they assert IndexedDB truth, not write-cache truth. A full process
// restart is not reachable from `dart test`, which stays the documented residual.
// The pinned subject includes `dynamic` itself (the post-reopen List<dynamic> shape on web), so
// the DCM ban is lifted for this file.
// ignore_for_file: avoid-dynamic
@TestOn('browser')
@Tags(['browser'])
library;

import 'package:checks/checks.dart';
import 'package:hive_ce/hive.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';
import '../../support/codecs/probe_codecs.dart';
import '../../support/fixtures/person.dart';

/// Part values at the edges of the 16-bit domain, where JS semantics would break first.
const boundaryParts = [0, 1, 42, partMask - 1, partMask];

void main() {
  feature('composite-key packing under web number semantics', () {
    scenarioOutline<({int Function(int, int) pack, (int, int) Function(int) unpack})>(
      'int packing round-trips exactly and stays non-negative at boundary values',
      examples: {
        'arithmetic packing (the 1.0 opt-in scheme)': (pack: arithPack, unpack: arithUnpack),
        'bit-shift packing (the 0.0.x reference lane)': (
          pack: bitShiftPack,
          unpack: bitShiftUnpack,
        ),
      },
      outline: (codec) {
        for (final primary in boundaryParts) {
          for (final secondary in boundaryParts) {
            final packed = codec.pack(primary, secondary);
            check(packed).isGreaterOrEqual(0);
            check(codec.unpack(packed)).equals((primary, secondary));
          }
        }
      },
    );

    scenario('the String composite round-trips at boundary values', () {
      for (final primary in boundaryParts) {
        for (final secondary in boundaryParts) {
          check(stringUnpack(stringPack(primary, secondary))).equals((primary, secondary));
        }
      }
    });
  });

  feature('hive_ce IndexedDB disk truth', () {
    scenario('keys, custom types, and collection casts survive close + reopen', () async {
      // hive_ce's web backend ignores the path (storage is IndexedDB); the argument only satisfies the shared VM/web signature.
      Hive
        ..init('hive_web_pins')
        ..registerAdapter(PersonAdapter(), override: true);

      // Unique per run: IndexedDB persists across tests within one browser session, and these pins must start from an empty box.
      final boxName = 'pins_${DateTime.now().millisecondsSinceEpoch}';
      var box = await Hive.openBox<Object>(boxName);
      await box.put(7, 'int-key');
      await box.put(arithPack(partMask, partMask), 'packed-key');
      await box.put('12:34', 'string-key');
      await box.put('person', const Person('web', 1));
      await box.put('list', <Person>[const Person('web-a', 2), const Person('web-b', 3)]);
      await box.close();

      box = await Hive.openBox<Object>(boxName);
      check(box.get(7)).equals('int-key');
      check(box.get(arithPack(partMask, partMask))).equals('packed-key');
      check(box.get('12:34')).equals('string-key');
      check(box.get('person')).equals(const Person('web', 1));

      final raw = box.get('list');
      check(raw is List<Person>).isFalse();
      check((raw! as List<dynamic>).cast<Person>().first).equals(const Person('web-a', 2));

      await box.deleteFromDisk();
    });
  });
}
