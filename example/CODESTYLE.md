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
- **Hoist state-independent widgets out of a `ValueListenableBuilder` through its `child`
  parameter.** The `builder` re-runs on every notification, so anything inside it that doesn't
  depend on the value rebuilds for nothing. Pass it once as `child:` and take it back as the
  builder's third argument: `ValueListenableBuilder(valueListenable: vm.current, child: const
  PlatformIcon(...), builder: (_, currentOrNone, icon) => PlatformListTile(leading: icon, ...))`.

### Directory layout

Feature-first MVVM, mirroring the sibling examples:

- `lib/main.dart`: the app shell (`Hive.initFlutter()` + `PlatformApp` with the per-platform theme
  data).
- `lib/features/<feature>/`: one folder per demo, holding `<feature>_view.dart` +
  `<feature>_view_model.dart` (plus a `widgets/` subfolder when a widget serves only that feature).
- `lib/features/core/`: shared building blocks: `data/constants/` (theme), `observers/` (the
  `LogPanelObserver` feeding the live event panel), `views/` (the home hub), `widgets/`
  (`DemoScaffold`, `DemoIntro`, `LogPanel`).

One primary public class per file, file name matching (as in the package). Imports follow the
package's same-area/cross-area split (see [`#idioms-imports`](../CODESTYLE.md#idioms-imports)), with
the **feature** as the area: an import within the **same feature** uses the relative-from-file path
(bare `sibling.dart`, or `../sub/x.dart` inside the feature), and one from a **different feature**
uses the root-relative path (`/features/<feature>/...`). `prefer_relative_imports` is on, and a
leading-`/` path is still a relative import (anchored at `lib/`); tests reach `lib/` through the
package URI.

### Views and view-models

- A view is a `StatelessWidget` whose `build` returns
  `MVVM.builder(viewModel: XxxViewModel(), viewBuilder: ...)`, wrapping its body in a
  `DemoScaffold(title: ...)`.
- A view-model is a `final class XxxViewModel extends ViewModel`. Expose state through getters; name
  mutation handlers `on<Thing>Changed` / `on<Thing>Toggled`. A boolean handler takes a named
  `{required bool value}` (per `avoid_positional_boolean_parameters`); `value` is the assigned-value
  parameter, exempt from the package's [predicate-naming rule](../CODESTYLE.md#naming) the same way a
  setter's `value` is. The view adapts it:
  `onChanged: (value) => viewModel.onThingToggled(value: value)`.

### View-model member ordering

Members in a `ViewModel` sit in a fixed top-to-bottom order, so every VM reads the same way. Tiers
1 and 2 are usually absent here (pmvvm builds through `init()`, and these demos inject nothing):

1. externally injected (DI) services (usually none here)
2. constructor (usually none here)
3. value-notifiers and state-changing vars (the fields mutated to drive a rebuild)
4. other internal vars (`late final _box`, stream subscriptions, open-latches)
5. const / static config, public before private
6. `init()`
7. public getters and setters
8. getter-like / setter-like methods (accessor substitutes; usually none here)
9. other methods (the `on<Thing>` action handlers)
10. private helper methods (a private getter counts as one)
11. `onUnmount()` (dispose), always last

Getters are **not** co-located with the field they front: a private notifier is tier 3, its
exposing getter tier 7 (so the `_prettyPrint` / `prettyPrint` / `setPrettyPrint` triad from the
state-management section above spreads across tiers 3 / 7 / 8; that snippet shows the pattern, not
the in-class placement). `init()` and `onUnmount()` bookend the members as the lifecycle pair.

### Widget composition

- **Import base widgets from `package:flutter/widgets.dart`, not `material_ui` / `cupertino_ui`.**
  Platform-adaptive widgets come from `platform_adaptive_widgets`; the framework base
  (`StatelessWidget`, `Column`, `Padding`, `ValueListenableBuilder`, ...) comes from
  `flutter/widgets.dart`. When a view genuinely needs a Material- or Cupertino-only symbol (`Theme`,
  `IconButton`, `MaterialPageRoute`), import it from `material_ui` / `cupertino_ui` behind an
  explicit `show`, so the material/cupertino surface a file touches stays visible at the top.
- **Row / Column spacing goes through the `spacing:` property, never `SizedBox` / `Padding`
  interspersed between children.** For a one-off gap that isn't between flex children, reach for
  [`Gap`](https://pub.dev/packages/gap) (it takes no axis argument, unlike `SizedBox`), not a
  child-less `Padding`. `spacing:` covers every gap the demos need, so `gap` isn't a dependency yet.
- **Simple, single-use sub-trees stay inline; don't extract a widget for them.** Pull a private
  `StatelessWidget` out only when the sub-tree is reused (like the hub's `_DemoTile`) or complex
  enough to earn a name; a one-off `ValueListenableBuilder` or list reads fine inline in `build`.
  Still **no `Widget _buildX()` helpers** (DCM `avoid-returning-widgets`), and a `switch` that
  yields a widget goes in a local inside `build`, not a helper method.
- **Discard unused callback parameters with `_`**, `BuildContext` most often: a
  `ValueListenableBuilder` `builder: (_, value, _)`, a `ListView.builder` `itemBuilder: (_, index)`.
  Keep the `build(BuildContext context)` override's parameter named (it is the signature), and keep
  a callback's context only when a *fresher* one than the enclosing scope's is actually needed.
- **Let type arguments infer where the arguments pin them**: `MVVM.builder(viewModel: FooVm(), ...)`
  and `ValueListenableBuilder(valueListenable: vm.x, ...)`, not `MVVM<FooVm>.builder` or
  `ValueListenableBuilder<T>`. Keep an explicit argument only where inference can't reach it (a
  `push<void>` over a route it can't pin).
- **Widget classes are fields-before-constructor**, same as the package
  [`#class-structure`](../CODESTYLE.md#class-structure): the `final` fields, then the `const`
  constructor, then `build`. That inverts the usual Flutter constructor-first habit, on purpose.
- **In the widget tree, prefer collection-`for` / `if` / spread to `.map(...).toList()`.** The
  package's [pipeline-over-comprehension rule](../CODESTYLE.md#idioms-collection-literals) is a
  *domain* rule; the View is its exception. A `children:` list is an eager `List<Widget>`
  regardless, so laziness buys nothing, and
  `[Header(), for (final item in items) ItemTile(item), if (isLoading) Spinner()]` reads as the
  tree it builds, where the spread-of-a-pipeline form (`...items.map(ItemTile.new)`) staples
  machinery into it. Domain transforms stay pipelines; the view stays a tree.

### Icons

Prefer `platform_icons` (`PlatformIcon(PlatformIcons.x)`); reach for
`platformValue(material:, cupertino:)` only when the glyph isn't in the library. The stack is
mobile-adaptive: `platformValue` throws on desktop/web, so the example targets Android and iOS.

### Tests

BDD suites use [`bdd_framework`](https://pub.dev/packages/bdd_framework) (`BddFeature`, `Bdd(...)
.scenario().given().when().then().run(...)`) with `checks` for assertions, and they target the
**view-models** against real hive on a temp dir: `bdd_framework`'s `run` wraps plain `test()`, not
`testWidgets`, so widget pumping stays out of the Gherkin suites by design.

**Name the system-under-test local `sut`, never `vm` or the view-model's type.** The `feature`,
`scenario`, and given/when/then lines already say which system is under test and how it should
behave, so the variable holding it shouldn't restate the type; `sut` keeps the run body reading as
"drive the subject, check the result" whichever view-model it wraps, and keeps same-shaped bodies
portable across suites. Declare it once in the harness (`late KeyedViewModel sut;`) and use `sut`
throughout.

**Input values live in `.example(val('name', value))` rows, read back in `run` through the context
(`ctx.example.val('name') as T`), never scattered as literals through the run body.** This is the
example-app twin of the package rule that parameters live in one place as named tables; `run`
executes once per example row, so same-shaped scenarios collapse into one scenario with rows (the
dual-query demo's two axes and its no-match case are one scenario, four rows). Rendering is
covered by plain `testWidgets` smokes (the hub tile check); `checks` has no finder API, so bridge a
`flutter_test` finder by evaluating it: `check(find.text('...').evaluate()).length.equals(1)`. When
something animates indefinitely (a spinner), drive fixed `pump()`s, never `pumpAndSettle`. Rationale
in the package [`CODESTYLE.md`](../CODESTYLE.md#test-style).
