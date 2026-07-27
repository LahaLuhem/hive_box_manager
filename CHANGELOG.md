## [1.1.0] - 2026-07-27
### Added
- \[#17\] Bring back `putAllBy`/`putAllGrouped`, the 0.0.x self-keying batch write

### Changed
- **BREAKING**: renamed `IterableBox` to `ListBox` and `LazyIterableBox` to `LazyListBox`. Members, contracts, and on-disk frames are unchanged, so a find-and-replace on the two names is the entire migration. `Iterable` was a misnomer: the box takes and returns a `List`, hive rejects non-`List` iterables at write time, and the name would have made the planned `SetBox` look like a subtype rather than a sibling, with no room for `Map` at all.

### Fixed
- \[#13\] Correct the DualKeyBox overhead figures and name their real cause
- \[#14\] Reduce DualKeyBox eager reads to near-native Hive speed

## [1.0.0] - 2026-07-22
### Added
- `KeyedBox` and `LazyKeyedBox`: typed key/value boxes with ready-made `get`, `put`, `update`, `delete`, `clear`, and `watch`.
- `SingleValueBox` and `LazySingleValueBox`: single-slot boxes for one value (a token, one config blob, the theme), reading 0.0.x single-box data in place.
- `IterableBox` and `LazyIterableBox`: a typed list per key, reifying the element type at the read boundary so collections of custom types survive a restart.
- `DualKeyBox` and `LazyDualKeyBox`: two-part composite keys with folded reverse queries (`queryByPrimary` and `queryBySecondary`).
- Key-codec seam (`KeyCodec` and `DualKeyCodec`) with shipped `IntKeyCodec`, `StringKeyCodec`, `StringCompositeDualCodec`, and `PackedIntDualCodec` (bit-identical to the 0.0.x `.bitShift` keys, so those boxes read in place).
- `BoxObserver` and `PrintingBoxObserver` for per-instance semantic event observation, with typed `TypedBoxEvent` and `LazyTypedBoxEvent` watch events.
- Write-path key validation that rejects out-of-range int keys and oversized String keys with an `ArgumentError`, before hive can silently corrupt the box.

### Changed
- Rewritten from scratch as an fpdart-first surface: reads return `Option` or `TaskOption`, writes and lifecycle effects return `Task`, acquisition encodes openness, and there is no `null` and no `defaultValue`. Breaking change from 0.0.x; see MIGRATION.md.
- Raised the Dart SDK floor to 3.12.0.
- Raised the `hive_ce` constraint to ^2.19.3.

### Fixed
- `watch()` no longer crashes on delete: eager events carry the removed value and lazy events carry an `Option`, replacing the 0.0.x nullable-cast crash.
- Collections of custom types no longer leak `dynamic` or throw on the first read after a restart (hive\_ce issue #150), via the `IterableBox` read-boundary reification.
- Lowered the `meta` lower bound to ^1.14.0 so Flutter apps resolve the package against the Flutter-pinned `meta`.

### Removed
- Removed the entire 0.0.x API: `BoxManager` and `LazyBoxManager`, the `SingleIndex` and `CollectionLazyBoxManager` managers, the `DualIntIndex` and `QueryDualIntIndex` families, plus `defaultValue`, `tryGet`, `getAll`, `storedIds`, `watchStream`, and `assignManagerLogCallback`. See MIGRATION.md for the mapping to 1.0.
- Dropped `collection` from the runtime dependencies.

## [0.0.8] - 2026-07-05
### Changed
- Loosen final classes for tesing mockability

## [0.0.7] - 2026-01-23
### Added
- delete from disk
- some box based extensions

### Changed
- Much better Readme

### Removed
- `delete` from SingleBox

## [0.0.6] - 2025-11-26
### Added
- expose watchable stream
- box.keys proxy for the managers

## [0.0.5] - 2025-11-07
### Added
- forgotten putAll for eager box manager

## [0.0.4] - 2025-11-07
### Added
- Add eager box variant for dual boxes

## [0.0.3+1] - 2025-11-06
### Added
- Some missing clears from all box types

## [0.0.3] - 2025-11-04
### Changed
- single place setter for LogCallback to reduce constructor boilerplate

## [0.0.2] - 2025-11-03
### Added
- Query variant for retrieving by either of the indices

## [0.0.1] - 2025-11-03
### Added
- Simple BoxManagers
- Single BoxManagers
- Collection BoxManagers
- (Lazy) Dual Int Index LazyBoxManager

[1.1.0]: https://github.com/LahaLuhem/hive_box_manager/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.8...1.0.0
[0.0.8]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.7...0.0.8
[0.0.7]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.6...0.0.7
[0.0.6]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.5...0.0.6
[0.0.5]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.4...0.0.5
[0.0.4]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.3+1...0.0.4
[0.0.3+1]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.3...0.0.3+1
[0.0.3]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.2...0.0.3
[0.0.2]: https://github.com/LahaLuhem/hive_box_manager/compare/0.0.1...0.0.2
[0.0.1]: https://github.com/LahaLuhem/hive_box_manager/releases/tag/%version%
