Example-app code style. Package (library) style lives in [`../CODESTYLE.md`](../CODESTYLE.md);
example scope and facts live in [`.ai/AGENTS.md`](.ai/AGENTS.md).

The example inherits the package's strict lint set (via `include: ../analysis_options.yaml`),
relaxing only `public_member_api_docs`. The package's generic style applies here: explicit types,
`final` by default, the collection-`for` and functional-pipeline idioms, and static dot shorthands.
The package CODESTYLE is pure-Dart, so the Flutter-specific conventions it doesn't cover live below.

## Example-specific conventions

### State management (pmvvm)

Use a scoped `ValueNotifier` (exposed as a `ValueListenable` getter) + `ValueListenableBuilder` for
state that rebuilds a **small** part of a view. Only call `notifyListeners()` on the `ViewModel`
(which rebuilds the whole `MVVM.builder` subtree) when **many** sites must update together.

- **Why:** `notifyListeners()` rebuilds everything under the view's consumer; if a control only
  changes its own widget, rebuilding the whole screen is wasteful. The flip side: one
  `ValueListenableBuilder` per field is O(n) subscriptions, so when a single change touches many
  places at once, one `notifyListeners()` beats many builders.
- **How to apply:** back the field with a private `ValueNotifier<T>`, expose a `ValueListenable<T>`
  getter, wrap only the dependent widget in a `ValueListenableBuilder`, write through a small setter
  that assigns `.value`, and dispose the notifier in the VM's `dispose()`.

  ```dart
  // Prefer: only the switch rebuilds on toggle.
  final _prettyPrint = ValueNotifier(false);
  ValueListenable<bool> get prettyPrint => _prettyPrint;
  void setPrettyPrint({required bool value}) => _prettyPrint.value = value;

  // Over: rebuilds the whole MVVM subtree for a one-widget change.
  var _prettyPrint = false;
  void setPrettyPrint({required bool value}) {
    _prettyPrint = value;
    notifyListeners();
  }
  ```

- **List-typed reactive state uses `ListNotifier` (from `listenable_collections`), not a
  `ValueNotifier<List<T>>`.** A `ValueNotifier` only notifies on identity change, so a growing list
  forces you to rebuild a fresh `List` on every mutation (`value = [x, ...value]`) just to fire a
  notification, which is boilerplate and easy to get wrong. `ListNotifier<T>` is itself a
  `ValueListenable<List<T>>` you mutate in place (`insert`, `removeLast`, `clear`) with a
  notification per change, so the getter and `ValueListenableBuilder` are the same while the writes
  read as ordinary list ops. A demo that streams box events into a live log is the natural fit.

### Directory layout

Feature-first MVVM, mirroring the sibling examples:

- `lib/main.dart`: the app shell (`Hive.initFlutter()` + `PlatformApp` with the per-platform theme
  data).
- `lib/features/<feature>/`: one folder per demo, holding `<feature>_view.dart` +
  `<feature>_view_model.dart` (plus a `widgets/` subfolder when a widget serves only that feature).
- `lib/features/core/`: shared building blocks: `data/constants/` (theme), `observers/` (the
  `LogPanelObserver` feeding the live event panel), `views/` (the home hub), `widgets/`
  (`DemoScaffold`, `DemoIntro`, `LogPanel`).

One primary public class per file, file name matching (as in the package). Imports inside `lib/`
stay relative (`prefer_relative_imports` is on); tests reach `lib/` through the package URI.

### Views and view-models

- A view is a `StatelessWidget` whose `build` returns
  `MVVM.builder(viewModel: XxxViewModel(), viewBuilder: ...)`, wrapping its body in a
  `DemoScaffold(title: ...)`.
- A view-model is a `final class XxxViewModel extends ViewModel`. Expose state through getters; name
  mutation handlers `on<Thing>Changed` / `on<Thing>Toggled`. A boolean handler takes a named
  `{required bool value}` (per `avoid_positional_boolean_parameters`); the view adapts it:
  `onChanged: (value) => viewModel.onThingToggled(value: value)`.

### Widget composition

- **No `Widget _buildX()` helpers** (DCM `avoid-returning-widgets`): extract a private
  `StatelessWidget` instead. A `switch` that yields a widget goes in a local inside `build`, not a
  helper method.
- Let generic type arguments infer when the arguments already pin them.

### Icons

Prefer `platform_icons` (`PlatformIcon(PlatformIcons.x)`); reach for
`platformValue(material:, cupertino:)` only when the glyph isn't in the library. The stack is
mobile-adaptive: `platformValue` throws on desktop/web, so the example targets Android and iOS.

### Tests

BDD suites use [`bdd_framework`](https://pub.dev/packages/bdd_framework) (`BddFeature`, `Bdd(...)
.scenario().given().when().then().run(...)`) with `checks` for assertions, and they target the
**view-models** against real hive on a temp dir: `bdd_framework`'s `run` wraps plain `test()`, not
`testWidgets`, so widget pumping stays out of the Gherkin suites by design.

**Input values live in `.example(val('name', value))` rows, read back in `run` through the context
(`ctx.example.val('name') as T`), never scattered as literals through the run body.** This is the
example-app twin of the package rule that parameters live in one place as named tables; `run`
executes once per example row, so same-shaped scenarios collapse into one scenario with rows (the
dual-query demo's two axes and its no-match case are one scenario, four rows). Rendering is
covered by plain `testWidgets` smokes (the hub tile check); `checks` has no finder API, so bridge a
`flutter_test` finder by evaluating it: `check(find.text('...').evaluate()).length.equals(1)`. When
something animates indefinitely (a spinner), drive fixed `pump()`s, never `pumpAndSettle`. Rationale
in the package [`CODESTYLE.md`](../CODESTYLE.md#test-style).
