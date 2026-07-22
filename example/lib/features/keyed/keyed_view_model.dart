import 'dart:async';

import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:listenable_collections/listenable_collections.dart';
import 'package:material_ui/material_ui.dart' show TextEditingController;
import 'package:pmvvm/pmvvm.dart';

import '../core/observers/log_panel_observer.dart';

/// Drives the eager keyed demo: an int-keyed `KeyedBox` of strings, read synchronously and
/// mutated through lazy tasks run at the handler edge.
final class KeyedViewModel extends ViewModel {
  final observer = LogPanelObserver();
  final valueController = TextEditingController();
  final entries = ListNotifier<(int, String)>();

  KeyedBox<String, int>? _box;

  late final Future<void> _opened;

  @override
  void init() {
    _opened = _open();
    unawaited(_opened);
  }

  /// Completes once the box is open and the first listing is loaded; awaitable by tests (and
  /// by anything that wants a splash gate).
  Future<void> get ready => _opened;

  Future<void> onAddPressed() async {
    final box = _box;
    final value = valueController.text.trim();
    if (box == null || value.isEmpty) return;

    final nextKey = box.keys.fold(0, (highest, key) => key > highest ? key : highest) + 1;
    await box.put(nextKey, value).run();
    valueController.clear();

    _refresh();
  }

  Future<void> onDeletePressed(int key) async {
    final box = _box;
    if (box == null) return;

    await box.delete(key).run();

    _refresh();
  }

  Future<void> _open() async {
    _box = await KeyedBox.open<String, int>('demo_keyed', observer: observer).run();

    _refresh();
  }

  void _refresh() {
    final box = _box;
    if (box == null) return;

    // Eager reads are synchronous: the whole listing rebuilds straight off the box cache.
    entries
      ..clear()
      ..addAll(box.keys.map((key) => (key, box.getOr(key, '?'))));
  }

  @override
  void onUnmount() {
    valueController.dispose();
    entries.dispose();

    super.onUnmount();
  }
}
