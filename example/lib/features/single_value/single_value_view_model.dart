import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:fpdart/fpdart.dart' show None, Option;
import 'package:hive_box_manager/hive_box_manager.dart';
import 'package:hive_ce/hive.dart' show HiveAesCipher;
import 'package:material_ui/material_ui.dart' show TextEditingController;
import 'package:pmvvm/pmvvm.dart';

import '../core/observers/log_panel_observer.dart';

/// Drives the encrypted single-value demo: a lazy box holding one AES-encrypted token, with the
/// current value fed entirely by the box's own watch stream.
final class SingleValueViewModel extends ViewModel {
  final observer = LogPanelObserver();
  final tokenController = TextEditingController();
  final _current = ValueNotifier<Option<String>>(const None());

  late final LazySingleValueBox<String> _box;
  StreamSubscription<Option<String>>? _subscription;

  // Demo-only fixed key so the box reopens across runs; real apps generate one with
  // Hive.generateSecureKey() and keep it in platform secure storage.
  static final _demoKey = List<int>.filled(32, 42);

  @override
  void init() {
    _box = LazySingleValueBox<String>(
      'demo_secret',
      cipher: HiveAesCipher(_demoKey),
      observer: observer,
    );

    // The watch stream is the single source of truth for the current value.
    _subscription = _box.watch().listen((value) => _current.value = value);
    unawaited(_box.get().run().then((value) => _current.value = value));
  }

  ValueListenable<Option<String>> get current => _current;

  Future<void> onSavePressed() async {
    final token = tokenController.text.trim();
    if (token.isEmpty) return;

    await _box.set(token).run();
    tokenController.clear();
  }

  Future<void> onClearPressed() => _box.clear().run();

  @override
  void onUnmount() {
    unawaited(_subscription?.cancel());
    tokenController.dispose();
    _current.dispose();

    super.onUnmount();
  }
}
