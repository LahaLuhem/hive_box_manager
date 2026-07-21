// The 1.0 reverse-query strategy: lazy decode-and-filter over the live key set, no side state.
@Tags(['unit'])
library;

import 'package:checks/checks.dart';
import 'package:hive_box_manager/src/codec/dual/string_composite_dual_codec.dart';
import 'package:hive_box_manager/src/query/scan_query_index.dart';
import 'package:test/test.dart';

import '../../support/bdd.dart';

void main() {
  const codec = StringCompositeDualCodec();
  final liveKeys = <Object>[];
  final scan = ScanQueryIndex<int, int>(rawKeys: () => liveKeys, codec: codec);

  setUp(liveKeys.clear);

  feature('ScanQueryIndex', () {
    scenario('filters raw keys by the primary part', () {
      liveKeys.addAll([codec.encode(1, 10), codec.encode(1, 11), codec.encode(2, 10)]);

      check(scan.rawKeysByPrimary(1)).deepEquals(['1:10', '1:11']);
    });

    scenario('filters raw keys by the secondary part', () {
      liveKeys.addAll([codec.encode(1, 10), codec.encode(1, 11), codec.encode(2, 10)]);

      check(scan.rawKeysBySecondary(10)).deepEquals(['1:10', '2:10']);
    });

    scenario('no matches means an empty result, never an absence', () {
      liveKeys.add(codec.encode(1, 10));

      check(scan.rawKeysByPrimary(99)).isEmpty();
    });

    scenario('scans the live key set, not a snapshot taken at construction', () {
      check(scan.rawKeysByPrimary(1)).isEmpty();

      liveKeys.add(codec.encode(1, 10));

      check(scan.rawKeysByPrimary(1)).deepEquals(['1:10']);
    });

    scenario('the maintenance hooks are callable no-ops (scan keeps no side state)', () {
      check(() {
        scan
          ..afterWrite('1:10', 1, 10)
          ..afterDelete('1:10', 1, 10);
      }).returnsNormally();
    });
  });
}
