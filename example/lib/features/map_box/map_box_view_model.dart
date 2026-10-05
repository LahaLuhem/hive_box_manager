import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:listenable_collections/listenable_collections.dart';
import 'package:material_ui/material_ui.dart' show TextEditingController;
import 'package:pmvvm/pmvvm.dart';

import '/features/core/observers/log_panel_observer.dart';

/// Drives the eager map-box demo: a map of settings per user, where saving a name that's already
/// there swaps its value in place.
final class MapBoxViewModel() extends ViewModel {
  final observer = LogPanelObserver();
  final nameController = TextEditingController();
  final valueController = TextEditingController();
  final settings = MapNotifier<String, String>();
  final _selectedUser = ValueNotifier(userIds.first);

  MapBox<String, String, int>? _box;

  late final Future<void> _opened;

  static const userIds = [1, 2, 3];

  @override
  void init() {
    _opened = _open();
    unawaited(_opened);
  }

  ValueListenable<int> get selectedUser => _selectedUser;

  /// Completes once the box is open and the first listing has loaded. Await it in tests.
  Future<void> get ready => _opened;

  void onUserSelected(int? userId) {
    if (userId == null) return;

    _selectedUser.value = userId;
    _refresh();
  }

  Future<void> onSavePressed() async {
    final box = _box;
    final name = nameController.text.trim();
    final value = valueController.text.trim();
    if (box == null || name.isEmpty || value.isEmpty) return;

    // addAll merges like Map.addAll, so a name that's already there keeps its place.
    await box.addAll(_selectedUser.value, {name: value}).run();
    nameController.clear();
    valueController.clear();

    _refresh();
  }

  Future<void> onRemovePressed(String name) async {
    final box = _box;
    if (box == null) return;

    await box.remove(_selectedUser.value, name).run();

    _refresh();
  }

  Future<void> _open() async {
    _box = await MapBox.open<String, String, int>('demo_settings', observer: observer).run();

    _refresh();
  }

  void _refresh() {
    final box = _box;
    if (box == null) return;

    settings
      ..clear()
      ..addAll(box.getOr(_selectedUser.value));
  }

  @override
  void onUnmount() {
    nameController.dispose();
    valueController.dispose();
    settings.dispose();
    _selectedUser.dispose();

    super.onUnmount();
  }
}
