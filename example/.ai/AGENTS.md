# AGENTS.md for `example/`

Tool-agnostic brief for the runnable demo app under `example/`. Package (library) conventions live
in the parent [`AGENTS.md`](../AGENTS.md); example-specific code style lives in
[`CODESTYLE.md`](CODESTYLE.md). Read both before working in this subdirectory.

> **Setup phase.** The example was just scaffolded (`flutter create --template=app`); the demos are
> built out as the `1.0` redo lands. The conventions below are the target shape. The concrete demo
> list and the package wiring (`hive_box_manager: { path: ../ }`, the stack deps) are **TODO**.

## Scope

- Runnable demo of `hive_box_manager`, wired to the parent package via
  `hive_box_manager: { path: ../ }`.
- Not published to pub.dev (`publish_to: 'none'` in `pubspec.yaml`). No semver discipline; it may
  freely depend on Flutter and ecosystem packages.
- Local only, no publish impact. Keep it building and analysing clean on the strict lint set (the
  example inherits the package's `analysis_options.yaml` via `include`). Its CI (a `flutter analyze`
  + `dependency_validator` job) is wired when the example is fleshed out.

## Architecture

Feature-first MVVM on the maintainer's standard example stack, mirroring the sibling examples
(`list_smith`, `platform_adaptive_widgets`, `better_internet_connectivity_checker`):

- **State**: `pmvvm` (`MVVM.builder` + `ViewModel`). See [`CODESTYLE.md`](CODESTYLE.md) for the
  reactivity rule (scoped `ValueNotifier` vs `notifyListeners`) and the view / view-model shape.
- **Surfaces**: `platform_adaptive_widgets` (Material on Android, Cupertino on iOS), with
  `material_ui` / `cupertino_ui` for the design libraries and `platform_icons` for icons.
- **Layout**: `lib/main.dart` (app shell) + `lib/app/` (scopes) + `lib/features/` (one folder per
  demo, plus `features/core/` for shared pieces). Full layout in [`CODESTYLE.md`](CODESTYLE.md).

**TODO (as the redo lands):** the concrete demo hub. The plan is one demo per Manager kind (a simple
box, a single-value box, a collection box, a dual-index / reverse-query box), each showing the
fpdart read/write surface, over a shared `DemoScaffold` and fake data sources under `features/core/`.

**Adding a demo:** create `lib/features/<name>/<name>_view.dart` + `_view_model.dart`, add a tile to
the home hub, and a smoke scenario to the widget tests. Reuse `DemoScaffold` and the `core` helpers.

## Mobile-targeted

The example's surface stack (`platform_adaptive_widgets`) is Android/iOS only: `platformValue` (and
`context.platformIcon`) throw on desktop/web, so run the demo on a mobile device or simulator. This
is a property of the demo's UI stack, not of `hive_box_manager` itself, which is pure Dart and runs
anywhere (Dart server, CLI, web, Flutter). If a platform-agnostic demo is wanted later, the UI stack
is the only thing tying it to mobile.
