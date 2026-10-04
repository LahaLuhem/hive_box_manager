import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Theme;

/// One-liner context card at the top of each demo screen.
class const DemoIntro({required final String text, super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}
