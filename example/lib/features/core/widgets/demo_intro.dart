import 'package:material_ui/material_ui.dart';

/// One-liner context card at the top of each demo screen.
class DemoIntro extends StatelessWidget {
  const DemoIntro({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}
