import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show IconButton;
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '/features/core/widgets/demo_intro.dart';
import '/features/core/widgets/demo_scaffold.dart';
import 'map_box_view_model.dart';

class const MapBoxView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MVVM.builder(
    viewModel: MapBoxViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'MapBox (eager)',
      observer: vm.observer,
      body: Column(
        children: [
          const DemoIntro(
            text:
                'A map of settings per user. Saving a setting that is already there swaps in the '
                'new value where the old one sat.',
          ),
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 8),
            child: ValueListenableBuilder(
              valueListenable: vm.selectedUser,
              builder: (_, selected, _) => PlatformSegmentButton(
                choices: MapBoxViewModel.userIds,
                segmentBuilder: (userId) => Text('User $userId'),
                selectedChoice: selected,
                onSelectionChanged: vm.onUserSelected,
              ),
            ),
          ),
          Padding(
            padding: const .symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                Expanded(
                  child: PlatformTextField(controller: vm.nameController, hintText: 'Setting'),
                ),
                Expanded(
                  child: PlatformTextField(
                    controller: vm.valueController,
                    hintText: 'Value',
                    onSubmitted: (_) => vm.onSavePressed(),
                  ),
                ),
                PlatformButton.icon(
                  onPressed: vm.onSavePressed,
                  icon: const PlatformIcon(PlatformIcons.checkMark, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: vm.settings,
              builder: (_, settings, _) => ListView(
                children: [
                  for (final MapEntry(key: name, :value) in settings.entries)
                    PlatformListTile(
                      title: Text(name),
                      subtitle: Text(value),
                      trailing: IconButton(
                        icon: const PlatformIcon(PlatformIcons.delete, size: 18),
                        onPressed: () => vm.onRemovePressed(name),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
