import 'package:flutter/widgets.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '/features/core/widgets/demo_intro.dart';
import '/features/core/widgets/demo_scaffold.dart';
import 'dual_query_view_model.dart';

class DualQueryView extends StatelessWidget {
  const DualQueryView({super.key});

  @override
  Widget build(BuildContext context) => MVVM.builder(
    viewModel: DualQueryViewModel(),
    viewBuilder: (context, vm) => DemoScaffold(
      title: 'DualKeyBox (lazy)',
      observer: vm.observer,
      body: Column(
        children: [
          const DemoIntro(
            text:
                'Entries addressed by (user, day). Seed a grid, then reverse-query by either '
                'part: an honest O(K) scan, plain empty list when nothing matches.',
          ),
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                PlatformButton.icon(
                  onPressed: vm.onSeedPressed,
                  icon: const PlatformIcon(PlatformIcons.add, size: 18),
                  label: const Text(
                    'Seed ${DualQueryViewModel.gridSide}x${DualQueryViewModel.gridSide} grid',
                  ),
                ),
                Expanded(
                  child: PlatformTextField(
                    controller: vm.partController,
                    hintText: 'Part (1..${DualQueryViewModel.gridSide})',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const .symmetric(horizontal: 16),
            child: Row(
              spacing: 8,
              children: [
                PlatformButton.icon(
                  onPressed: vm.onQueryByUserPressed,
                  icon: const PlatformIcon(PlatformIcons.search, size: 18),
                  label: const Text('By user'),
                ),
                PlatformButton.icon(
                  onPressed: vm.onQueryByDayPressed,
                  icon: const PlatformIcon(PlatformIcons.search, size: 18),
                  label: const Text('By day'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: vm.results,
              builder: (_, results, _) => ListView.builder(
                itemCount: results.length,
                itemBuilder: (_, index) => PlatformListTile(title: Text(results[index])),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
