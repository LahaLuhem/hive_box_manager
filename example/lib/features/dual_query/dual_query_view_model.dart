import 'dart:async';

import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:listenable_collections/listenable_collections.dart';
import 'package:material_ui/material_ui.dart' show TextEditingController;
import 'package:pmvvm/pmvvm.dart';

import '../core/observers/log_panel_observer.dart';

/// Drives the dual-key demo: a lazy (user, day)-addressed box, seeded as a grid and reverse
/// queried by either part through the folded O(K) scan.
final class DualQueryViewModel extends ViewModel {
  final observer = LogPanelObserver();
  final partController = TextEditingController(text: '1');
  final results = ListNotifier<String>();

  static const gridSide = 3;

  late final LazyDualKeyBox<String, int, int> _box;

  @override
  void init() {
    _box = LazyDualKeyBox<String, int, int>('demo_grid', observer: observer);
  }

  @override
  void onUnmount() {
    partController.dispose();
    results.dispose();
    super.onUnmount();
  }

  Future<void> onSeedPressed() => _box.putAll({
    for (var user = 1; user <= gridSide; user++)
      for (var day = 1; day <= gridSide; day++) (user, day): 'user $user / day $day',
  }).run();

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
}
