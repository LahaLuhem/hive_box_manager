import 'package:material_ui/material_ui.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '../core/widgets/demo_intro.dart';
import '../core/widgets/demo_scaffold.dart';
import 'keyed_view_model.dart';

class KeyedView extends StatelessWidget {
  const KeyedView({super.key});

  @override
  Widget build(BuildContext context) => MVVM<KeyedViewModel>.builder(
    viewModel: KeyedViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'KeyedBox (eager)',
      observer: vm.observer,
      body: Column(
        children: [
          const DemoIntro(
            text:
                'An int-keyed eager box: reads are synchronous Options straight from memory, '
                'writes are Tasks run at the edge.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: PlatformTextField(
                    controller: vm.valueController,
                    hintText: 'Value to store',
                    onSubmitted: (_) => vm.onAddPressed(),
                  ),
                ),
                const SizedBox(width: 8),
                PlatformButton.icon(
                  onPressed: vm.onAddPressed,
                  icon: const PlatformIcon(PlatformIcons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(child: _EntryList(vm: vm)),
        ],
      ),
    ),
  );
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.vm});

  final KeyedViewModel vm;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<(int, String)>>(
    valueListenable: vm.entries,
    builder: (context, entries, _) => ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final (key, value) = entries[index];

        return PlatformListTile(
          title: Text(value),
          subtitle: Text('key $key'),
          trailing: IconButton(
            icon: const PlatformIcon(PlatformIcons.delete, size: 18),
            onPressed: () => vm.onDeletePressed(key),
          ),
        );
      },
    ),
  );
}
