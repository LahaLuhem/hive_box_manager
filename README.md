[![Package checks](https://github.com/LahaLuhem/hive_box_manager/actions/workflows/package.yml/badge.svg?branch=master)](https://github.com/LahaLuhem/hive_box_manager/actions/workflows/package.yml)
[![Coverage Status](https://coveralls.io/repos/github/LahaLuhem/hive_box_manager/badge.svg?branch=master)](https://coveralls.io/github/LahaLuhem/hive_box_manager?branch=master)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/LahaLuhem/hive_box_manager/pulls)
[![Pub Version](https://img.shields.io/pub/v/hive_box_manager.svg)](https://pub.dev/packages/hive_box_manager)
[![Pub Points](https://img.shields.io/pub/points/hive_box_manager?logo=dart)](https://pub.dev/packages/hive_box_manager/score)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![GitHub issues](https://img.shields.io/github/issues/LahaLuhem/hive_box_manager.svg)](https://github.com/LahaLuhem/hive_box_manager/issues)
[![GitHub closed issues](https://img.shields.io/github/issues-closed/LahaLuhem/hive_box_manager.svg)](https://github.com/LahaLuhem/hive_box_manager/issues?q=is%3Aissue+is%3Aclosed)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/LahaLuhem/hive_box_manager.svg)](https://github.com/LahaLuhem/hive_box_manager/pulls)
[![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed/LahaLuhem/hive_box_manager.svg)](https://github.com/LahaLuhem/hive_box_manager/pulls?q=is%3Apr+is%3Aclosed)

Typed, fpdart-first façades over [hive_ce](https://pub.dev/packages/hive_ce) boxes. No `null`s,
no bare `Future`s, no hand-written CRUD. Pick the box that fits your data and get on with it.

> ⬆️ **Upgrading from `0.0.x`?** 1.0 is a from-scratch rewrite with a new API, but your data
> almost always reads in place. [MIGRATION.md](MIGRATION.md) walks you through it.

Hive is already fast. What it doesn't hand you is a surface that's pleasant to live with, and
that's the gap this fills:

- 🎯 **Absence is a type, not `null`.** Reads return an `Option` (or `TaskOption`), so "not
  there" is a case the compiler makes you handle, never a crash waiting to happen.
- 🧰 **CRUD is already written.** get, put, update, delete, clear and watch ship on every box, so
  you stop rewriting the same boilerplate for every type you store.
- 🧩 **Four boxes for four real shapes of data**, each in an eager and a lazy flavour, so the box
  fits the problem instead of the other way round.
- 🛡️ **Safer than raw Hive.** The write path rejects keys release-mode `hive_ce` accepts and then
  silently corrupts on, and `ListBox` closes the `List<dynamic>` trap that breaks a naive
  `Box<List<T>>` on its first post-restart read. Both pinned by tests against upstream, not assumed.
- 🚀 **At near-native Hive speed.\*** Reads cost 1 to 22 ns per op against raw `hive_ce`, and
  effects that reach disk stay within 2 to 4%.
  <br><sub>\* Two surfaces cost more than that, and [what that costs](#-what-that-costs) prices
  every surface rather than quoting one flattering average.</sub>

Pure Dart, so it runs anywhere Hive does: Flutter apps, Dart servers, CLIs, and the web.

<!-- TOC start (generated with https://github.com/derlin/bitdowntoc) -->

- [🧭 Which box?](#-which-box)
- [🚀 Quickstart](#-quickstart)
    * [1. Install](#1-install)
    * [2. Wire up Hive once](#2-wire-up-hive-once)
    * [3. Open a box and use it](#3-open-a-box-and-use-it)
- [🧰 The box families](#-the-box-families)
    * [🔑 KeyedBox](#-keyedbox)
    * [📍 SingleValueBox](#-singlevaluebox)
    * [🗂️ ListBox](#-listbox)
    * [🔗 DualKeyBox](#-dualkeybox)
- [🎛️ Make it yours](#-make-it-yours)
- [📏 Eager or lazy? (measured)](#-eager-or-lazy-measured)
- [🛡️ Safer than raw hive, at near-native speed](#-safer-than-raw-hive-at-near-native-speed)
    * [⚡ What that costs](#-what-that-costs)
    * [⚡ Codec choice](#-codec-choice)
- [🗺️ Roadmap](#-roadmap)

<!-- TOC end -->

## 🧭 Which box?

Start here. Match what you're storing to a family, then grab its eager or lazy variant.

| You're storing                | Reach for               | Real-world fit                              |
|-------------------------------|-------------------------|---------------------------------------------|
| Many values, one key each     | `KeyedBox<T, K>`        | users, todos, cache entries                 |
| Exactly one value             | `SingleValueBox<T>`     | a session token, the theme, one config blob |
| A list of values per key      | `ListBox<T, K>`         | tags per post, history per day              |
| Values addressed by two parts | `DualKeyBox<T, K1, K2>` | (user, day) events, (row, column) grids     |

Every family has an eager and a `Lazy...` twin; [Eager or lazy?](#-eager-or-lazy-measured) picks
the axis with measured numbers. Reverse queries ("everything for this user") live on the
dual-key family.

## 🚀 Quickstart

### 1. Install

```sh
dart pub add hive_box_manager hive_ce
```

### 2. Wire up Hive once

Engine setup stays `hive_ce`'s, [exactly as its docs show](https://docs.hive.isar.community):

```dart
import 'package:hive_ce/hive.dart';

Hive.init(appDataDirectory.path); // Hive.initFlutter() in Flutter apps
Hive.registerAdapter(TodoAdapter()); // usually generated by hive_ce_generator
```

None of `hive_ce`'s symbols are re-exported. This package wraps boxes; the engine stays yours.

### 3. Open a box and use it

```dart
import 'package:hive_box_manager/hive_box_manager.dart';

final todos = await KeyedBox.open<Todo, int>('todos').run();

await todos.put(1, Todo('write the README')).run();

final found = todos.get(1); // Option<Todo>: Some when present, None when absent
final orEmpty = todos.getOr(2, Todo.empty());

todos.watch().listen((event) => print('${event.key} -> ${event.value}'));
```

That's the whole loop. Reads come straight off the in-memory cache, so they're synchronous;
writes are lazy `Task`s you `run()` at the edge. And since you get the box from an `open`
factory, holding one means it's already open. There's no init step to forget.

## 🧰 The box families

Here's the good part: all four families wear the **same surface**, so you learn it once and it
carries everywhere. The shape, in short:

- Absence is always `Option` / `TaskOption`, never `null` and never a magic default.
- Effects are always `Task`s. Nothing touches disk until you `.run()`, so pipelines compose first
  and fire once.
- `watch` is typed, and `close()` / `deleteFromDisk()` are terminal (reacquire, don't reuse).

<details>
<summary>📋 <b>The full method table</b> (KeyedBox shown; the others mirror it)</summary>

|                                                     | `KeyedBox<T, K>`              | `LazyKeyedBox<T, K>`              |
|-----------------------------------------------------|-------------------------------|-----------------------------------|
| `get(key)`                                          | `Option<T>`                   | `TaskOption<T>`                   |
| `getOr(key, fallback)`                              | `T`                           | `Task<T>`                         |
| `values`                                            | `Iterable<T>`                 | `Task<List<T>>`                   |
| `keys` / `contains` / `length`                      | sync                          | sync, after first open            |
| `put` / `putAll` / `delete` / `deleteAll` / `clear` | `Task<Unit>`                  | `Task<Unit>`                      |
| `putAllBy(values, {key})`                           | `Task<Unit>`                  | `Task<Unit>`                      |
| `update(key, fn, {ifAbsent})`                       | `Task<T>`                     | `Task<T>`                         |
| `watch({key})`                                      | `Stream<TypedBoxEvent<T, K>>` | `Stream<LazyTypedBoxEvent<T, K>>` |
| `flush` / `compact` / `close` / `deleteFromDisk`    | `Task<Unit>`                  | `Task<Unit>`                      |

Watch is typed on both axes: an eager delete event still carries the value that was removed; a
lazy event carries an `Option<T>` that's `None` on deletes, because a lazy box holds no value to
hand back.

`putAllBy` is sugar for the common case where each value already carries its own key, so
`Map.fromIterables(values.map((v) => v.id), values)` at the call site becomes
`putAllBy(values, key: (v) => v.id)`. It builds no intermediate map, which measures about
**74 ns per entry** cheaper (0.94x) than writing the map yourself. `DualKeyBox` takes the same shape
with two extractors (`primary:` and `secondary:`), and `ListBox` has `putAllGrouped`, which collects
a flat iterable into one stored list per key.

Keep `putAll` for everything else, and that is most cases: the key often isn't derivable from the
value at all (primitives, values with no id, keys that come from a grid or a legacy key set), and on
`ListBox` only `putAll` can store an **empty** list, since grouping never produces one.

</details>

### 🔑 KeyedBox

Many values, each under its own key. The everyday workhorse.

<details>
<summary>Eager and lazy, side by side</summary>

**Eager** keeps every value in memory once the box opens, so reads are synchronous:

```dart
final todos = await KeyedBox.open<Todo, int>('todos').run();

await todos.put(1, Todo('write the README')).run();
final found = todos.get(1); // Option<Todo>
```

**Lazy** constructs synchronously and opens itself on the first effect. Values come off disk per
read, so reads are effects too:

```dart
final archive = LazyKeyedBox<Todo, String>('archive');

await archive.put('2025-w1', Todo('ship 1.0')).run(); // first effect auto-opens
final found = await archive.get('2025-w1').run(); // TaskOption<Todo>
await archive.ensureInitialised().run(); // optional explicit warm-up
```

</details>

### 📍 SingleValueBox

One value, no keys. A token, a theme, one config blob.

<details>
<summary>Set, read, clear, watch</summary>

```dart
final session = await SingleValueBox.open<String>('session_token').run();

await session.set('abc123').run();
final token = session.get(); // Option<String>
await session.clear().run(); // the one unset; the next get() is None

session.watch().listen((token) => print(token)); // Some on set, None on clear
```

The value sits under a fixed internal slot, the same one `0.0.x` single boxes used, so that data
reads in place. `LazySingleValueBox` is the same surface on the lazy axis. `update` mirrors
`Map.update`, and `getOr(fallback)` reads with a default.

</details>

### 🗂️ ListBox

A list of values per key. Tags on a post, history for a day.

<details>
<summary>List ergonomics, and the sharp edge it files off</summary>

Hive reads collections back as `List<dynamic>` no matter what you wrote
([issue #150](https://github.com/IO-Design-Team/hive_ce/issues/150)), so a plain
`Box<List<Person>>` opens fine and then throws on the first read after a restart. `ListBox`
restores the element type at the read boundary and stacks list helpers on top:

```dart
final tags = await ListBox.open<String, int>('post_tags').run();

await tags.put(1, ['flutter', 'dart']).run(); // any Iterable; stored as a private copy
await tags.add(1, 'hive').run(); // append; an absent key becomes [value]
await tags.remove(1, 'dart').run(); // first occurrence; an absent key is a no-op

final postTags = tags.getOr(1); // List<String>: unmodifiable view, empty when absent
final maybe = tags.get(1); // Option<List<String>>: None = absent, Some([]) = stored empty
```

Worth knowing:

- Lists you read out are **unmodifiable views**; lists you put in are **copied**. Mutating your
  original afterwards never leaks into the box. `add` / `addAll` / `remove` are read-modify-writes,
  O(n) in the stored list.
- **Absent isn't the same as empty.** `get` keeps them apart; `getOr` folds both to `[]` on
  purpose.
- **List semantics only:** order preserved, duplicates allowed. Sets, maps, and nested
  collections of custom types stay out (the read-boundary cast can't fix inner reification). Model
  richer shapes as adapter-registered value types instead.
- `LazyListBox` is the same surface on the lazy axis.

</details>

### 🔗 DualKeyBox

Two natural dimensions to your data (user + day, row + column). Address it by both parts, query by
either.

<details>
<summary>Lookups, reverse queries, and the codec choice</summary>

```dart
final events = await DualKeyBox.open<Event, int, int>('user_events').run();

await events.put(userId, dayIndex, event).run();

final one = events.get(userId, dayIndex); // Option<Event>: exact lookups stay O(1)
final usersWeek = events.queryByPrimary(userId); // List<Event>: everything for this user
final everyoneToday = events.queryBySecondary(dayIndex); // List<Event>: everyone, this day
```

Queries hand back a plain (possibly empty) list, and in 1.0 they're an honest **O(K) scan** over
the live key set: free until you call one, exact when you do, documented instead of hidden. Where
a whole key is needed (`keys`, `putAll`, watch events) it travels as a `(primary, secondary)`
record. `LazyDualKeyBox` matches the surface on the lazy axis (queries return `Task<List<T>>`).

Both parts round-trip through one `DualKeyCodec`. `(int, int)` defaults to the safe
`StringCompositeDualCodec` (full-range parts, negatives included, no ceilings). If both parts fit
in 16 bits and the numbers matter to you, opt into `PackedIntDualCodec`
(`codec: const PackedIntDualCodec()`). It packs both parts into a single u32 key and is
**bit-identical to the old `0.0.x` `.bitShift` scheme**, so those boxes read in place. The two
codecs trade off measurably; [Codec choice](#-codec-choice) has the head-to-head. Rolling your own
part types? Implement `DualKeyCodec<K1, K2>` and keep the encoding bijective, or reverse queries
will lie to you.

</details>

## 🎛️ Make it yours

The boxes do their work through seams you can swap. Every `open` (and every lazy constructor)
takes these, all optional:

- **`codec:`** a `KeyCodec<K>` (or `DualKeyCodec<K1, K2>`) for key types beyond `int` / `String`.
- **`observer:`** a `BoxObserver` to hear semantic events. Silent when you pass nothing.
- **`cipher:`** a `hive_ce` `HiveCipher` for an encrypted box.
- **hive pluggables** (`keyComparator`, `compactionStrategy`, `crashRecovery`), passed straight
  through to the engine.

<details>
<summary>🗝️ A custom key type</summary>

`int` and `String` work out of the box. Anything else brings a codec:

```dart
final class DateKeyCodec implements KeyCodec<DateTime> {
  const DateKeyCodec();

  @override
  Object encode(DateTime key) => key.toIso8601String();

  @override
  DateTime decode(Object rawKey) => DateTime.parse(rawKey as String);
}

final byDay = await KeyedBox.open<Todo, DateTime>(
  'by_day',
  codec: const DateKeyCodec(),
).run();
```

`encode` has to produce an `int` in `0..0xFFFFFFFF` or a `String` of at most 255 UTF-8 bytes.
That's hive's raw key domain, and staying inside it is what keeps your data safe (more on that
just below).

</details>

<details>
<summary>📣 Observing what your code does</summary>

Pass an observer and you'll hear every semantic event. Pass none and dispatch costs nothing:

```dart
final todos = await KeyedBox.open<Todo, int>(
  'todos',
  observer: const PrintingBoxObserver(), // dart:developer log, DevTools-filterable
).run();
```

Extend `BoxObserver` and override only the events you care about; `PrintingBoxObserver` is the
ready-made sink. Two notes on the engine side: `hive_ce`'s own warnings stay on its global logging
channel (its [logging options](https://docs.hive.isar.community) filter them), and the
[Hive Inspector DevTools extension](https://pub.dev/packages/hive_ce) is handy for eyeballing box
contents while your observer reports what the code did to them.

</details>

## 📏 Eager or lazy? (measured)

Folklore says "lazy opens instantly and saves all the memory." The maintainer benchmark (macOS
Apple Silicon, AOT, hive_ce 2.19.3) disagrees:

- **Opening costs about the same either way**, and it scales with file size: ~70 ms at 100K
  int-keyed entries, ~3.4 s at 1M (lazy shaves 5 to 10% off, not an order of magnitude). Hive parses
  every frame to build the keystore on any open. What lazy skips is holding onto the *values*.
- **Keys always live in RAM**, eager or lazy: 22 to 64 MB at 100K entries, 210 to 340 MB at 1M.
  The spread is the key encoding, not the box kind: String keys run 50 to 80% heavier than int keys.
- **Reads are where they split.** An eager get is ~1.1 to 1.4 µs from memory; a lazy get pays for
  a disk read at ~26 µs.

Open cost tracks file size on both axes (the two lines sit right on top of each other), while
reads are where they part ways:

![Box open time by box size: eager and lazy overlap, both rising with size](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/open_eager_vs_lazy.png)

![Per-read latency by box size on a log scale: eager reads from memory sit far below lazy reads from disk](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/read_eager_vs_lazy.png)

So reach for **eager** on hot, value-heavy-*read* boxes that fit comfortably in RAM, and **lazy**
on value-heavy boxes you read only now and then. Neither opens "instantly" at scale, and keys are
a RAM cost you pay regardless.

## 🛡️ Safer than raw hive, at near-native speed

Release-mode `hive_ce` takes an out-of-range int key or an oversized String key without
complaint, then corrupts quietly: keys wrap into other slots, and an oversized String key can make
the whole box file unreadable on its next open. This package rejects exactly those keys with an
`ArgumentError` at the call site, before anything reaches disk.

### ⚡ What that costs

There is no single number, and any package that gives you one is quoting the surface that flattered
it. Wrapper cost depends on how expensive the thing being wrapped is, so it splits by surface:

| Surface                                                             | Wrapper cost                                                        | Read as                                                   |
|---------------------------------------------------------------------|---------------------------------------------------------------------|-----------------------------------------------------------|
| `KeyedBox` / `SingleValueBox`, memory reads (get, contains, values) | 1 to 22 ns per op                                                   | free                                                      |
| Any effect that reaches disk (put, delete, lazy get)                | 300 to 700 ns per op, 2 to 4%                                       | free, disk dominates                                      |
| `ListBox` reads                                                     | ~290 ns per `get` + ~1.8 ns per element                             | 3.0x on one-element lists, 1.1x on thousand-element lists |
| Batch writes (`putAll`, `deleteAll`)                                | 1 to 21 ns per entry                                                | free                                                      |
| Open time, keystore RAM, file size                                  | no measurable difference                                            | identical                                                 |
| `DualKeyBox` eager get                                              | 1.02x (+3 to +21 ns per op)                                         | free                                                      |
| `DualKeyBox` `putAll`                                               | +45 to +85 ns per entry (int parts), +230 to +310 ns (String parts) | 1.09x to 1.36x by batch size, see below                   |

<details>
<summary>Why percentages are the wrong unit for most of this</summary>

Some operations are cheap enough that one extra call frame doubles them while costing nothing that
matters. A same-slot `SingleValueBox.get` is ~13 ns of raw hive, so the `Option` allocation and codec
dispatch take it to ~24 ns: that is **+89%**, and it is also **+11 ns**. Walking an eager `values`
iterable is +32% and +3 ns.

Quoting those percentages would be a lie by arithmetic, so the table gives nanoseconds wherever the
underlying op is that cheap, and percentages only where the denominator is a real disk round-trip.
`benchmark/python/overhead.py` enforces the same split, and refuses to stand behind a run whose
median and minimum disagree.

Precision, honestly: repeated passes reproduce the *bands* above and the ordering, not two
significant figures on any single lane. Treat each figure as an order of magnitude.

</details>

**`DualKeyBox` is free to read and costs per entry to batch-write.** Eager get is 1.02x, lazy gets
1.01x, reverse queries 0.93 to 1.03x, open and memory are unchanged, and exact lookups stay O(1).

`putAll` is the one exception: it rebuilds its record-keyed batch into a raw-keyed map, at +45 to
+85 ns per entry for `int` parts and +230 to +310 ns for `String` parts. That reads as anywhere
from 1.09x to 1.36x, but the ratio only moves because raw's own per-entry cost grows with the batch
while the wrapper's stays flat, so take the nanoseconds and ignore the multiple.

<details>
<summary>Where a composite key can cost you, measured</summary>

This surface takes `(K1, K2)` records, and there is one way to encode them that costs ~25x the
others. Eight variants of the same two-part encode, each changing exactly one thing from the one
above it:

![Eight key-shape variants by ns per op: the three that route a generic-parameterised record through a checked parameter cost about 355 ns, every other shape sits near 15 ns](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/key_shape_attribution.png)

Records are free. Generics are free. An extra adapter call frame is free. What costs ~350 ns is a
**record type built from a class's own type parameters, sitting in a checked parameter position**:
the subtype check resolves through the instantiated type-argument vector and misses AOT's inline
subtype-test cache. Widening that parameter to `Object` and casting inside does not help, because it
is the same check written out, and making the record type concrete hides the cost while leaving the
trap armed for whoever re-parameterises it next.

So `DualKeyBox` encodes both parts as separate scalar arguments, which is the free side of that
line. `benchmark/key_shape_bench.dart` prices every variant and its reader asserts each
relationship, so this stays measured rather than remembered.

</details>

**`ListBox` prices differently**, because raw hive has no list-valued box to compare against. Its
baseline is the code you would hand-write, and there are two of those. Against the version with a
`.cast<T>()` at the read boundary, `ListBox` costs the ~290 ns plus ~1.8 ns per element above (the
per-element part is the cast view's type check, one per element you actually touch). Against the
version without a cast, your hand-roll is *faster and broken*: a stored `List<Person>` reads back as
`List<dynamic>` after a restart and the cast throws. Memory matches a correct hand-roll on every
lane, reads included, so the read view really is copy-free; it just isn't check-free.

### ⚡ Codec choice

Two dual-key codecs ship, and they trade off like this:

| Operation                     | packed int                         | String composite |
|-------------------------------|------------------------------------|------------------|
| eager get, 100K entries       | 119 ms                             | 163 ms           |
| box open (eager), 100K        | 77 ms                              | 144 ms           |
| putAll, 100K                  | 132 ms                             | 232 ms           |
| reverse query, 100K           | 6.2 ms                             | 11.6 ms          |
| keystore RSS after open, 100K | 35 MB                              | 64 MB            |
| box file size, 100K           | 1.9 MB                             | 2.7 MB           |
| lazy get / single put         | codec-indifferent (disk dominates) |                  |

Medians measured **through `DualKeyBox` itself** (macOS Apple Silicon, AOT, constant 1-byte values to
isolate key cost), not through a hand-rolled stand-in. Web is unmeasured; its ordering is assumed to
follow the VM. `StringCompositeDualCodec` is the safe default; reach for `PackedIntDualCodec` when
these wins matter and both parts fit in 16 bits.

The table rows are the 100K slice of these curves; the gap widens as boxes grow:

![Eager get time by box size: packed-int stays below String composite, the gap widening with scale](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/codec_get_scaling.png)

![Keystore RAM after open by box size: packed-int stays below String composite](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/codec_rss_scaling.png)

## 🗺️ Roadmap

<details>
<summary>What's on the table for 1.x (and what will never land)</summary>

Additive candidates for 1.x, in no committed order:

- **Indexed reverse queries** for very large (>100K) datasets: an inverted-index strategy on
  `LazyDualKeyBox`, swapping out the O(K) scan behind the same query methods.
- **IsolatedHive support** behind the box-acquisition seam (`hive_ce` itself recommends it for
  multi-isolate apps), plus `BoxCollection` wrapping if there's demand.
- **A migration helper API** (1.0 documents recipes in [MIGRATION.md](MIGRATION.md) for now).
- **Sets, maps, and nested collections** on the value-codec seam (`ListBox` is list-only
  today).
- **A consumer fakes package** (in-memory façades for app tests) and Flutter companions (a
  `ValueListenable` adapter), as separate packages so the core stays pure Dart.

Deliberately **never** wrapped, because they fight the typed, codec-addressed key model:
auto-increment `add` / `addAll`, index-based `getAt` / `putAt` / `deleteAt` / `keyAt`, `toMap`,
and `valuesBetween`. Reach for a raw `hive_ce` box where those genuinely fit.

</details>
