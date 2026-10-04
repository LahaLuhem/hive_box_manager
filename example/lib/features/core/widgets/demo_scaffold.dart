import 'package:flutter/widgets.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';

import '../observers/log_panel_observer.dart';
import 'log_panel.dart';

/// The shared demo frame: scaffold, title, the demo body, and the event log docked underneath when the
/// demo wires an observer.
class const DemoScaffold({
  required final String title,
  required final Widget body,
  final LogPanelObserver? observer,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final observer = this.observer;

    return PlatformScaffold(
      appBarData: PlatformAppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            if (observer != null) LogPanel(observer: observer),
          ],
        ),
      ),
    );
  }
}
