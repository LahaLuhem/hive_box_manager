import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show IconButton, Theme;
import 'package:platform_icons/platform_icons.dart';

import '../observers/log_panel_observer.dart';

/// The live box-event feed docked under every demo: one `ValueListenableBuilder` over the
/// observer's `ListNotifier`, so each dispatched event repaints only this panel.
class LogPanel extends StatelessWidget {
  final LogPanelObserver observer;

  const new({required this.observer, super.key});

  static const _panelHeight = 180.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: _panelHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Box events (BoxObserver)', style: theme.textTheme.labelLarge),
              const Spacer(),
              IconButton(
                icon: const PlatformIcon(PlatformIcons.delete, size: 18),
                onPressed: observer.clearEntries,
              ),
            ],
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: observer.entries,
              builder: (_, entries, _) => ListView.builder(
                itemCount: entries.length,
                itemBuilder: (_, index) => Text(
                  entries[index],
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
