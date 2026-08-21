import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageRoute;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show MaterialPageRoute;
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';
import 'package:platform_icons/platform_icons.dart';

import '/features/dual_query/dual_query_view.dart';
import '/features/keyed/keyed_view.dart';
import '/features/list_box/list_box_view.dart';
import '/features/single_value/single_value_view.dart';

/// The demo hub: one tile per box family.
class HomeHubView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => PlatformScaffold(
    appBarData: const PlatformAppBar(title: Text('hive_box_manager demos')),
    body: SafeArea(
      child: ListView(
        children: [
          _DemoTile(
            icon: PlatformIcons.document,
            title: 'KeyedBox',
            subtitle: 'Eager CRUD: sync Option reads, Task writes, typed watch',
            builder: (_) => const KeyedView(),
          ),
          _DemoTile(
            icon: PlatformIcons.lockFilled,
            title: 'SingleValueBox',
            subtitle: 'One encrypted value on the lazy axis, tracked via watch()',
            builder: (_) => const SingleValueView(),
          ),
          _DemoTile(
            icon: PlatformIcons.folder,
            title: 'ListBox',
            subtitle: 'Tag lists per key: add / remove sugar, unmodifiable views',
            builder: (_) => const ListBoxView(),
          ),
          _DemoTile(
            icon: PlatformIcons.search,
            title: 'DualKeyBox',
            subtitle: '(user, day) composite keys with reverse queries by either part',
            builder: (_) => const DualQueryView(),
          ),
        ],
      ),
    ),
  );
}

class _DemoTile extends StatelessWidget {
  final PlatformIcons icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => PlatformListTile(
    leading: PlatformIcon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const PlatformIcon(PlatformIcons.forward, size: 16),
    onTap: () => Navigator.of(context).push<void>(
      platformLazyValue(
        material: () => MaterialPageRoute<void>(builder: builder),
        cupertino: () => CupertinoPageRoute<void>(builder: builder),
      ),
    ),
  );
}
