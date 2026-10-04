import 'dart:async';

import 'package:fpdart/fpdart.dart' show Task, Unit;
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:listenable_collections/listenable_collections.dart';
import 'package:material_ui/material_ui.dart' show TextEditingController;
import 'package:pmvvm/pmvvm.dart';

import '/features/core/observers/log_panel_observer.dart';

/// Drives the eager set-box demo: one set of tags that ignores case, so add and upsert differ only in
/// which spelling stays.
final class SetBoxViewModel extends ViewModel {
  final observer = LogPanelObserver();
  final tagController = TextEditingController();
  final tags = ListNotifier<String>();

  SetBox<String, int>? _box;

  late final Future<void> _opened;

  static const _tagsKey = 1;

  @override
  void init() {
    _opened = _open();
    unawaited(_opened);
  }

  /// Completes once the box is open and the tags have loaded. Await it in tests.
  Future<void> get ready => _opened;

  Future<void> onAddPressed() => _writeTypedTag((box, tag) => box.add(_tagsKey, tag));

  Future<void> onUpsertPressed() => _writeTypedTag((box, tag) => box.upsert(_tagsKey, tag));

  Future<void> onRemovePressed(String tag) async {
    final box = _box;
    if (box == null) return;

    await box.remove(_tagsKey, tag).run();

    _refresh();
  }

  Future<void> _open() async {
    _box = await SetBox.open<String, int>(
      'demo_tag_set',
      // Tags ignore case, so 'Flutter' and 'flutter' are one tag.
      idOf: (tag) => tag.toLowerCase(),
      observer: observer,
    ).run();

    _refresh();
  }

  Future<void> _writeTypedTag(
    Task<Unit> Function(SetBox<String, int> box, String tag) write,
  ) async {
    final box = _box;
    final tag = tagController.text.trim();
    if (box == null || tag.isEmpty) return;

    await write(box, tag).run();
    tagController.clear();

    _refresh();
  }

  void _refresh() {
    final box = _box;
    if (box == null) return;

    tags
      ..clear()
      ..addAll(box.getOr(_tagsKey));
  }

  @override
  void onUnmount() {
    tagController.dispose();
    tags.dispose();

    super.onUnmount();
  }
}
