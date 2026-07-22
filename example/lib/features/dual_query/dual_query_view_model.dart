import 'dart:async';

import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:listenable_collections/listenable_collections.dart';
import 'package:material_ui/material_ui.dart' show TextEditingController;
import 'package:pmvvm/pmvvm.dart';

import '/features/core/observers/log_panel_observer.dart';

/// Drives the dual-key demo: a lazy (user, day)-addressed box, seeded as a grid and reverse
/// queried by either part through the folded O(K) scan.
final class DualQueryViewModel extends ViewModel {
  final observer = LogPanelObserver();
  final partController = TextEditingController(text: '1');
  final results = ListNotifier<String>();

  late final LazyDualKeyBox<String, int, int> _box;

  static const gridSide = 3;

  @override
  void init() {
    _box = LazyDualKeyBox<String, int, int>('demo_grid', observer: observer);
  }

  Future<void> onSeedPressed() {
    final axis = Iterable.generate(gridSide, (i) => i + 1);
    final coords = axis.expand((user) => axis.map((day) => (user, day)));

    return _box
        .putAll(
          Map.fromIterables(coords, coords.map((coord) => 'user ${coord.$1} / day ${coord.$2}')),
        )
        .run();
  }

  Future<void> onQueryByUserPressed() async {
    final matches = await _box.queryByPrimary(_enteredPart).run();

    _showResults(matches);
  }

  Future<void> onQueryByDayPressed() async {
    final matches = await _box.queryBySecondary(_enteredPart).run();

    _showResults(matches);
  }

  int get _enteredPart => int.tryParse(partController.text.trim()) ?? 1;

  void _showResults(List<String> matches) => results
    ..clear()
    ..addAll(matches);

  @override
  void onUnmount() {
    partController.dispose();
    results.dispose();

    super.onUnmount();
  }
}
