import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:platform_adaptive_widgets/platform_adaptive_widgets.dart';

import '/features/core/data/constants/demo_theme.dart';
import '/features/core/views/home_hub_view.dart';

Future<void> main() async {
  // Engine setup stays hive_ce's one-liner; every box open below goes through the façades.
  await Hive.initFlutter();

  runApp(const HbmExampleApp());
}

class HbmExampleApp extends StatelessWidget {
  const HbmExampleApp({super.key});

  @override
  Widget build(BuildContext context) => PlatformApp(
    title: 'hive_box_manager demos',
    debugShowCheckedModeBanner: false,
    materialAppData: MaterialAppData(theme: DemoTheme.material),
    cupertinoAppData: const CupertinoAppData(theme: DemoTheme.cupertino),
    home: const HomeHubView(),
  );
}
