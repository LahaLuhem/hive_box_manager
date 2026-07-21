import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:listenable_collections/listenable_collections.dart';
import 'package:material_ui/material_ui.dart' show TextEditingController;
import 'package:pmvvm/pmvvm.dart';

import '../core/observers/log_panel_observer.dart';

/// Drives the eager iterable demo: tag lists per int key, mutated through the add / remove
/// sugar (read-modify-writes under the hood) and read back as unmodifiable views.
final class IterableViewModel extends ViewModel {
  final observer = LogPanelObserver();
  final tagController = TextEditingController();
  final tags = ListNotifier<String>();

  static const listKeys = [1, 2, 3];

  final _selectedKey = ValueNotifier(listKeys.first);
  ValueListenable<int> get selectedKey => _selectedKey;

  IterableBox<String, int>? _box;

  late final Future<void> _opened;

  /// Completes once the box is open and the first listing is loaded; awaitable by tests (and
  /// by anything that wants a splash gate).
  Future<void> get ready => _opened;

  @override
  void init() {
    _opened = _open();
    unawaited(_opened);
  }

  @override
  void onUnmount() {
    tagController.dispose();
    tags.dispose();
    _selectedKey.dispose();
    super.onUnmount();
  }

  void onKeySelected(int? key) {
    if (key == null) return;

    _selectedKey.value = key;
    _refresh();
  }

  Future<void> onAddPressed() async {
    final box = _box;
    final tag = tagController.text.trim();
    if (box == null || tag.isEmpty) return;

    await box.add(_selectedKey.value, tag).run();
    tagController.clear();

    _refresh();
  }

  Future<void> onRemovePressed(String tag) async {
    final box = _box;
    if (box == null) return;

    await box.remove(_selectedKey.value, tag).run();

    _refresh();
  }

  Future<void> _open() async {
    _box = await IterableBox.open<String, int>('demo_tags', observer: observer).run();

    _refresh();
  }

  void _refresh() {
    final box = _box;
    if (box == null) return;

    // getOr folds absent and stored-empty to the same empty view: the natural list default.
    tags
      ..clear()
      ..addAll(box.getOr(_selectedKey.value));
  }
}
