import 'package:material_ui/material_ui.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '../core/widgets/demo_intro.dart';
import '../core/widgets/demo_scaffold.dart';
import 'iterable_view_model.dart';

class IterableView extends StatelessWidget {
  const IterableView({super.key});

  @override
  Widget build(BuildContext context) => MVVM<IterableViewModel>.builder(
    viewModel: IterableViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'IterableBox (eager)',
      observer: vm.observer,
      body: Column(
        children: [
          const DemoIntro(
            text:
                'A list of tags per key: add and remove are read-modify-write sugar, and '
                'every list you read back is an unmodifiable view.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _KeySelector(vm: vm),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: PlatformTextField(
                    controller: vm.tagController,
                    hintText: 'Tag to add',
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
          Expanded(child: _TagList(vm: vm)),
        ],
      ),
    ),
  );
}

class _KeySelector extends StatelessWidget {
  const _KeySelector({required this.vm});

  final IterableViewModel vm;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: vm.selectedKey,
    builder: (context, selected, _) => PlatformSegmentButton<int>(
      choices: IterableViewModel.listKeys,
      segmentBuilder: (key) => Text('List $key'),
      selectedChoice: selected,
      onSelectionChanged: vm.onKeySelected,
    ),
  );
}

class _TagList extends StatelessWidget {
  const _TagList({required this.vm});

  final IterableViewModel vm;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: vm.tags,
    builder: (context, tags, _) => ListView.builder(
      itemCount: tags.length,
      itemBuilder: (context, index) => PlatformListTile(
        title: Text(tags[index]),
        trailing: IconButton(
          icon: const PlatformIcon(PlatformIcons.delete, size: 18),
          onPressed: () => vm.onRemovePressed(tags[index]),
        ),
      ),
    ),
  );
}
