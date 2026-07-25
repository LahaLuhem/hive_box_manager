// Render smoke: the hub builds under the adaptive stack (Material on the test platform) and
// shows one tile per box family. Plain testWidgets on purpose: bdd_framework wraps test(), not
// testWidgets, so widget pumping stays outside the Gherkin suites.
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hbm_example/features/core/views/home_hub_view.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the hub lists all four family demos', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeHubView()));

    for (final title in ['KeyedBox', 'SingleValueBox', 'ListBox', 'DualKeyBox']) {
      check(find.text(title).evaluate()).length.equals(1);
    }
  });
}
