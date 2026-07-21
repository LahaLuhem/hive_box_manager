import 'package:material_ui/material_ui.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';
import 'package:pmvvm/pmvvm.dart';

import '../core/widgets/demo_intro.dart';
import '../core/widgets/demo_scaffold.dart';
import 'dual_query_view_model.dart';

class DualQueryView extends StatelessWidget {
  const DualQueryView({super.key});

  @override
  Widget build(BuildContext context) => MVVM<DualQueryViewModel>.builder(
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                PlatformButton.icon(
                  onPressed: vm.onSeedPressed,
                  icon: const PlatformIcon(PlatformIcons.add, size: 18),
                  label: const Text(
                    'Seed ${DualQueryViewModel.gridSide}x${DualQueryViewModel.gridSide} grid',
                  ),
                ),
                const SizedBox(width: 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                PlatformButton.icon(
                  onPressed: vm.onQueryByUserPressed,
                  icon: const PlatformIcon(PlatformIcons.search, size: 18),
                  label: const Text('By user'),
                ),
                const SizedBox(width: 8),
                PlatformButton.icon(
                  onPressed: vm.onQueryByDayPressed,
                  icon: const PlatformIcon(PlatformIcons.search, size: 18),
                  label: const Text('By day'),
                ),
              ],
            ),
          ),
          Expanded(child: _ResultList(vm: vm)),
        ],
      ),
    ),
  );
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.vm});

  final DualQueryViewModel vm;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: vm.results,
    builder: (context, results, _) => ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) => PlatformListTile(title: Text(results[index])),
    ),
  );
}
