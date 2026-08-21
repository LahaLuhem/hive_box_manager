import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show IconButton;
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '/features/core/widgets/demo_intro.dart';
import '/features/core/widgets/demo_scaffold.dart';
import 'list_box_view_model.dart';

class ListBoxView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => MVVM.builder(
    viewModel: ListBoxViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'ListBox (eager)',
      observer: vm.observer,
      body: Column(
        children: [
          const DemoIntro(
            text:
                'A list of tags per key: add and remove are read-modify-write sugar, and '
                'every list you read back is an unmodifiable view.',
          ),
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 8),
            child: ValueListenableBuilder(
              valueListenable: vm.selectedKey,
              builder: (_, selected, _) => PlatformSegmentButton(
                choices: ListBoxViewModel.listKeys,
                segmentBuilder: (key) => Text('List $key'),
                selectedChoice: selected,
                onSelectionChanged: vm.onKeySelected,
              ),
            ),
          ),
          Padding(
            padding: const .symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: PlatformTextField(
                    controller: vm.tagController,
                    hintText: 'Tag to add',
                    onSubmitted: (_) => vm.onAddPressed(),
                  ),
                ),
                PlatformButton.icon(
                  onPressed: vm.onAddPressed,
                  icon: const PlatformIcon(PlatformIcons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: vm.tags,
              builder: (_, tags, _) => ListView.builder(
                itemCount: tags.length,
                itemBuilder: (_, index) => PlatformListTile(
                  title: Text(tags[index]),
                  trailing: IconButton(
                    icon: const PlatformIcon(PlatformIcons.delete, size: 18),
                    onPressed: () => vm.onRemovePressed(tags[index]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
