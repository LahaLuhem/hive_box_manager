# hive_box_manager demos

A runnable Flutter hub with one screen per box family, each docking a **live `BoxObserver` event
panel** so you can watch the semantic events (opens, reads, writes, deletes, errors) as you tap:

| Demo | Box | What to try |
|---|---|---|
| KeyedBox | eager, `<String, int>` | add and delete entries; reads are sync `Option`s |
| SingleValueBox | lazy + `HiveAesCipher` | save and clear an encrypted token; the screen tracks `watch()` |
| IterableBox | eager, tags per key | `add` / `remove` sugar, per-key lists, duplicates allowed |
| DualKeyBox | lazy, `(user, day)` keys | seed a grid, then reverse-query by either part |

Values are plain `String`s on purpose, so no `TypeAdapter` or codegen is involved; real apps
register adapters exactly as [hive_ce documents](https://docs.hive.isar.community).

## Run it

```sh
cd example
flutter run
```

The UI stack (`platform_adaptive_widgets`) is Android/iOS-adaptive and throws on other platforms,
so run on a mobile device or simulator. That's a property of the demo's UI, not of
`hive_box_manager`, which is pure Dart and runs anywhere Hive does.

## Tests

```sh
flutter test
```

Behaviour suites are BDD-shaped via `bdd_framework` and drive the view-models against real hive
on temp dirs; a plain widget smoke covers the hub rendering.
