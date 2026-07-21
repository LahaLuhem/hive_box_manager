# AGENTS.md for `example/`

Tool-agnostic brief for the runnable demo app under `example/`. Package (library) conventions live
in the parent [`AGENTS.md`](../AGENTS.md); example-specific code style lives in
[`CODESTYLE.md`](CODESTYLE.md). Read both before working in this subdirectory.

## Scope

- Runnable demo of `hive_box_manager`, wired to the parent package via
  `hive_box_manager: { path: ../ }`.
- Not published to pub.dev (`publish_to: 'none'` in `pubspec.yaml`). No semver discipline; it may
  freely depend on Flutter and ecosystem packages.
- Local only, no publish impact. Keep it building and analysing clean on the strict lint set (the
  example inherits the package's `analysis_options.yaml` via `include`, relaxing only
  `public_member_api_docs`). Its CI (a `flutter analyze` + `dependency_validator` job) is a
  tracked maintainer follow-up.

## Architecture

Feature-first MVVM on the maintainer's standard example stack, mirroring the sibling examples
(`list_smith`, `platform_adaptive_widgets`, `better_internet_connectivity_checker`):

- **State**: `pmvvm` (`MVVM.builder` + `ViewModel`). See [`CODESTYLE.md`](CODESTYLE.md) for the
  reactivity rule (scoped `ValueNotifier` vs `notifyListeners`) and the view / view-model shape.
- **Surfaces**: `platform_adaptive_widgets` (Material on Android, Cupertino on iOS), with
  `material_ui` / `cupertino_ui` for the design libraries and `platform_icons` for icons.
- **Layout**: `lib/main.dart` (app shell: `Hive.initFlutter()` + `PlatformApp`) + `lib/features/`
  (one folder per demo, plus `features/core/` for shared pieces). Full layout in
  [`CODESTYLE.md`](CODESTYLE.md).

**The demo hub**, one feature per box family, every screen docking the live `BoxObserver` event
panel from `features/core/`:

| Feature | Box | Shows |
|---|---|---|
| `keyed` | eager `KeyedBox<String, int>` | CRUD listing, sync `Option` reads, `Task` writes |
| `single_value` | lazy `LazySingleValueBox<String>` + `HiveAesCipher` | one encrypted token, state fed by `watch()` |
| `iterable` | eager `IterableBox<String, int>` | tag lists per key, `add` / `remove` sugar, unmodifiable views |
| `dual_query` | lazy `LazyDualKeyBox<String, int, int>` | (user, day) composite keys, reverse queries by either part |

Demo values are primitives (`String`) on purpose, so the example needs no `TypeAdapter` and no
codegen; the package README points real apps at `hive_ce_generator`.

**Adding a demo:** create `lib/features/<name>/<name>_view.dart` + `_view_model.dart`, add a tile to
the home hub, and a BDD suite under `test/features/<name>/`. Reuse `DemoScaffold` and the `core`
helpers.

## Mobile-targeted

The example's surface stack (`platform_adaptive_widgets`) is Android/iOS only: `platformValue` (and
`context.platformIcon`) throw on desktop/web, so run the demo on a mobile device or simulator. This
is a property of the demo's UI stack, not of `hive_box_manager` itself, which is pure Dart and runs
anywhere (Dart server, CLI, web, Flutter). If a platform-agnostic demo is wanted later, the UI stack
is the only thing tying it to mobile.
