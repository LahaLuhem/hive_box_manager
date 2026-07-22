import 'package:flutter/widgets.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';

import '../observers/log_panel_observer.dart';
import 'log_panel.dart';

/// The shared demo frame: adaptive scaffold + title, the demo body, and the live event log
/// panel docked underneath when the demo wires an observer.
class DemoScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final LogPanelObserver? observer;

  const DemoScaffold({required this.title, required this.body, this.observer, super.key});

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
