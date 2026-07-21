# Migrating from 0.0.x to 1.0

> 🚧 **Draft.** 1.0 is a from-scratch rewrite and a hard break from `0.0.x`. This guide is being
> assembled alongside the rewrite and is completed with the release docs pass.

## Your data: almost always compatible in place

1.0 keeps `0.0.x`'s on-disk conventions wherever they were sound, so most boxes open under the
new façades with no migration at all:

| 0.0.x box | 1.0 verdict |
|---|---|
| Simple (`BoxManager` / `LazyBoxManager`) | **reads in place** (same box names, keys, frames) |
| Single value (`SingleIndex*Manager`) | **reads in place** (the internal slot key is retained) |
| Collection (`CollectionLazyBoxManager`) | **reads in place** (same list frames; new read-boundary cast) |
| Dual `.bitShift` | **reads in place** via `PackedIntDualCodec` (bit-identical keys) |
| Dual `.negative` | one-time re-key needed; recipe below |

Box kind is not persisted by hive, so moving between eager and lazy façades is also free.

## Symbol map

| 0.0.x | 1.0 |
|---|---|
| `BoxManager` / `LazyBoxManager` | `KeyedBox` / `LazyKeyedBox` |
| `SingleIndexBoxManager` / `SingleIndexLazyBoxManager` | `SingleValueBox` / `LazySingleValueBox` |
| `CollectionLazyBoxManager<T, I>` | `LazyIterableBox<T, K>` (plus a new eager `IterableBox`) |
| `DualIntIndex*` + `QueryDualIntIndex*` + `BitShiftQuery*` | `DualKeyBox` / `LazyDualKeyBox` + a codec choice |
| `init(cipher)` | gone: eager `open(...)` factories / lazy auto-open; `cipher:` at construction |
| `defaultValue` (mandatory) | gone: `get` returns `Option`, `getOr` is the sugar |
| `tryGet` | `get` (absence-shaped: `Option` / `TaskOption`) |
| `getAll` / `tryGetAll` | `values` (plain; no `None`-on-empty conflation) |
| `watchStream()` (raw `BoxEvent`s) | `watch()` (typed events; deletes carry the value on eager) |
| `upsert` | `update` (mirrors `Map.update`) |
| `storedIds` | `keys` |
| `assignManagerLogCallback` + `LogPattern` | `observer:` (`BoxObserver`) at construction |
| `.bitShift` encoder | `codec: const PackedIntDualCodec()` |
| `.negative` encoder | re-key once; recipe below |

## Re-keying a `.negative` dual box

The 0.0.x `.negative` encoder wrote keys as `((primary + 16383) << 15) | (secondary + 16383)`
(range ±16383 per part). 1.0 doesn't reship it: the default `StringCompositeDualCodec` covers
negative parts natively, with no ceiling. Re-key once with a throwaway shim codec that reads the
legacy layout:

```dart
/// Reads keys the 0.0.x `.negative` encoder wrote. Only for the one-time migration below.
final class LegacyNegativeDualCodec implements DualKeyCodec<int, int> {
  const LegacyNegativeDualCodec();

  static const _offset = 16383;
  static const _partCeiling = 1 << 15;

  @override
  Object encode(int primary, int secondary) =>
      (primary + _offset) * _partCeiling + (secondary + _offset);

  @override
  (int, int) decode(Object rawKey) {
    final packed = rawKey as int;

    return (packed ~/ _partCeiling - _offset, packed % _partCeiling - _offset);
  }
}

Future<void> rekeyNegativeBox(String legacyName, String newName) async {
  final legacy = await DualKeyBox.open<MyValue, int, int>(
    legacyName,
    codec: const LegacyNegativeDualCodec(),
  ).run();
  final migrated = await DualKeyBox.open<MyValue, int, int>(newName).run();

  await migrated.putAll({for (final (p, s) in legacy.keys) (p, s): legacy.getOr(p, s, …)}).run();
  await legacy.deleteFromDisk().run();
}
```

Read every entry through the shim, write into a composite-keyed box, delete the legacy file.
Run it once at startup behind a "migrated" flag (a `SingleValueBox<bool>` works nicely).

## Behavioural changes worth re-reading

- **No `init()` anywhere.** Holding an eager box means it's open; lazy boxes open themselves on
  the first effect.
- **Absence is `Option`, defaults are gone.** Anywhere you relied on `defaultValue`, pass the
  fallback at the read (`getOr`).
- **Writes gate raw keys.** Out-of-range int keys and oversized String keys throw an
  `ArgumentError` at the call site instead of silently corrupting the box in release builds.
- **`close()` / `deleteFromDisk()` are terminal.** Reacquire a new instance instead of reusing
  the handle.
