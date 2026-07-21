import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoColors, CupertinoThemeData;
import 'package:material_ui/material_ui.dart';

/// One place for the demo look: Material gets a seeded scheme, Cupertino its tint.
abstract final class DemoTheme {
  static final material = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber));
  static const cupertino = CupertinoThemeData(primaryColor: CupertinoColors.systemYellow);
}
