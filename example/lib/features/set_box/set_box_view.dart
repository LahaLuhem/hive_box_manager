import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show IconButton;
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '/features/core/widgets/demo_intro.dart';
import '/features/core/widgets/demo_scaffold.dart';
import 'set_box_view_model.dart';

class const SetBoxView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MVVM.builder(
    viewModel: SetBoxViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'SetBox (eager)',
      observer: vm.observer,
      body: Column(
        children: [
          const DemoIntro(
            text:
                'One set of tags that ignores case, so "Flutter" and "flutter" are the same tag. '
                'Add keeps the spelling already stored, and upsert swaps in yours.',
          ),
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: PlatformTextField(
                    controller: vm.tagController,
                    hintText: 'Tag',
                    onSubmitted: (_) => vm.onAddPressed(),
                  ),
                ),
                PlatformButton.icon(
                  onPressed: vm.onAddPressed,
                  icon: const PlatformIcon(PlatformIcons.add, size: 18),
                  label: const Text('Add'),
                ),
                PlatformButton.icon(
                  onPressed: vm.onUpsertPressed,
                  icon: const PlatformIcon(PlatformIcons.pencil, size: 18),
                  label: const Text('Upsert'),
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
