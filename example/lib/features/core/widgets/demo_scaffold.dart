import 'package:material_ui/material_ui.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';

import '../observers/log_panel_observer.dart';
import 'log_panel.dart';

/// The shared demo frame: adaptive scaffold + title, the demo body, and the live event log
/// panel docked underneath when the demo wires an observer.
class DemoScaffold extends StatelessWidget {
  const DemoScaffold({required this.title, required this.body, this.observer, super.key});

  final String title;
  final Widget body;
  final LogPanelObserver? observer;

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
