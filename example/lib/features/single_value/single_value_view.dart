import 'package:fpdart/fpdart.dart' show Option;
import 'package:material_ui/material_ui.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '../core/widgets/demo_intro.dart';
import '../core/widgets/demo_scaffold.dart';
import 'single_value_view_model.dart';

class SingleValueView extends StatelessWidget {
  const SingleValueView({super.key});

  @override
  Widget build(BuildContext context) => MVVM<SingleValueViewModel>.builder(
    viewModel: SingleValueViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'SingleValueBox (lazy + encrypted)',
      observer: vm.observer,
      body: Column(
        children: [
          const DemoIntro(
            text:
                'One AES-encrypted value, no keys on the surface: the lazy box opens itself '
                'on the first effect, and this screen tracks it through watch().',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _CurrentToken(vm: vm),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: PlatformTextField(
                    controller: vm.tokenController,
                    hintText: 'Session token',
                    onSubmitted: (_) => vm.onSavePressed(),
                  ),
                ),
                const SizedBox(width: 8),
                PlatformButton.icon(
                  onPressed: vm.onSavePressed,
                  icon: const PlatformIcon(PlatformIcons.lockFilled, size: 18),
                  label: const Text('Save'),
                ),
                const SizedBox(width: 8),
                PlatformButton(
                  onPressed: vm.onClearPressed,
                  materialButtonVariant: MaterialButtonVariant.outlined,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    ),
  );
}

class _CurrentToken extends StatelessWidget {
  const _CurrentToken({required this.vm});

  final SingleValueViewModel vm;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Option<String>>(
    valueListenable: vm.current,
    builder: (context, current, _) => PlatformListTile(
      leading: const PlatformIcon(PlatformIcons.lock),
      title: Text(current.match(() => 'No token stored (None)', (token) => token)),
      subtitle: const Text('Some on set, None on clear: straight off watch()'),
    ),
  );
}
