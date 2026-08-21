import 'package:flutter/widgets.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '/features/core/widgets/demo_intro.dart';
import '/features/core/widgets/demo_scaffold.dart';
import 'single_value_view_model.dart';

class SingleValueView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MVVM.builder(
    viewModel: SingleValueViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'SingleValueBox (lazy + encrypted)',
      observer: vm.observer,
      body: Column(
        spacing: 16,
        children: [
          const DemoIntro(
            text:
                'One AES-encrypted value, no keys on the surface: the lazy box opens itself '
                'on the first effect, and this screen tracks it through watch().',
          ),
          ValueListenableBuilder(
            valueListenable: vm.current,
            child: const PlatformIcon(PlatformIcons.lock),
            builder: (_, currentOrNone, lockIconWidget) => PlatformListTile(
              leading: lockIconWidget,
              title: Text(currentOrNone.match(() => 'No token stored (None)', (token) => token)),
              subtitle: const Text('Some on set, None on clear: straight off watch()'),
            ),
          ),
          Padding(
            padding: const .symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: PlatformTextField(
                    controller: vm.tokenController,
                    hintText: 'Session token',
                    onSubmitted: (_) => vm.onSavePressed(),
                  ),
                ),
                PlatformButton.icon(
                  onPressed: vm.onSavePressed,
                  icon: const PlatformIcon(PlatformIcons.lockFilled),
                  label: const Text('Save'),
                ),
                PlatformButton(
                  onPressed: vm.onClearPressed,
                  materialButtonVariant: MaterialButtonVariant.outlined,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
