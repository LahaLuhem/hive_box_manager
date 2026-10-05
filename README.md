[![CI](https://github.com/LahaLuhem/hive_box_manager/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/LahaLuhem/hive_box_manager/actions/workflows/ci.yml)
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

<p align="center">
  <img src="https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/doc/screenshots/1-overview.png" width="260" alt="The example app's hub, with one demo per box family">
</p>

> ⬆️ **Upgrading from `0.0.x`?** 1.0 is a from-scratch rewrite with a new API, but your data
> almost always reads in place. [MIGRATION.md](MIGRATION.md) walks you through it.

Hive is already fast. What it doesn't hand you is a surface that's pleasant to live with, and
that's the gap this fills:

- 🎯 **Absence is a type, not `null`.** Reads return an `Option` (or `TaskOption`), so "not
  there" is a case the compiler makes you handle, never a crash waiting to happen.
- 🧰 **CRUD is already written.** get, put, update, delete, clear and watch ship on every box, so
  you stop rewriting the same boilerplate for every type you store.
- 🧩 **6 boxes for 6 real shapes of data**, each in an eager and a lazy flavour, so the box
  fits the problem instead of the other way round.
- 🛡️ **Safer than raw Hive.** The write path rejects keys release-mode `hive_ce` accepts and then
  silently corrupts on, and the collection boxes close the `dynamic` trap that breaks a naive
  `Box<List<T>>` or `Box<Map<K, V>>` on its first post-restart read. Both pinned by tests against
  upstream, not assumed.
- 🚀 **At near-native Hive speed.\*** Reads cost 1 to 22 ns per op against raw `hive_ce`, and
  effects that reach disk stay within 2 to 4%.
  <br><sub>\* 2 surfaces cost more than that, and [what that costs](#-what-that-costs) prices
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
    * [🧺 SetBox](#-setbox)
    * [📖 MapBox](#-mapbox)
    * [🔗 DualKeyBox](#-dualkeybox)
- [🎛️ Make it yours](#-make-it-yours)
- [📏 Eager or lazy? (measured)](#-eager-or-lazy-measured)
    * [💥 When a record won't decode](#-when-a-record-wont-decode)
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
| A set of values per key       | `SetBox<T, K>`          | members per team, favourites per user       |
| A map of values per key       | `MapBox<MK, MV, K>`     | prices per store, settings per user         |
| Values addressed by 2 parts   | `DualKeyBox<T, K1, K2>` | (user, day) events, (row, column) grids     |

Every family has an eager and a `Lazy...` twin. [Eager or lazy?](#-eager-or-lazy-measured) picks
the axis with measured numbers. Reverse queries ("everything for this user") live on the
dual-key family.

`MapBox` and `DualKeyBox` both find a value by 2 parts. `MapBox` stores each key's map as one
record, read and written whole, which suits small maps you use together. Reach for `DualKeyBox`
when entries change one at a time, maps grow large, or you look things up by the second part.

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

None of `hive_ce`'s symbols are re-exported. This package wraps boxes, and the engine stays yours.

<details>
<summary>A type from another package</summary>

One adapter over its `toJson` / `fromJson` is enough. Nested types need none of their own:

```dart
import 'dart:convert';

final class JsonAdapter<T> extends TypeAdapter<T> {
  JsonAdapter(this.typeId, {required this.toJson, required this.fromJson});

  @override
  final int typeId;
  final Map<String, Object?> Function(T value) toJson;
  final T Function(Map<String, Object?> json) fromJson;

  @override
  T read(BinaryReader reader) =>
      fromJson(jsonDecode(reader.readString()) as Map<String, Object?>);

  @override
  void write(BinaryWriter writer, T obj) => writer.writeString(jsonEncode(toJson(obj)));
}

Hive.registerAdapter(
  JsonAdapter<Invoice>(1, toJson: (invoice) => invoice.toJson(), fromJson: Invoice.fromJson),
);
```

For a sealed hierarchy, register it once for the base type.

</details>

### 3. Open a box and use it

```dart
import 'package:hive_box_manager/hive_box_manager.dart';

final todos = await KeyedBox.open<Todo, int>('todos').run();

await todos.put(1, Todo('write the README')).run();

final found = todos.get(1); // Option<Todo>: Some when present, None when absent
final orEmpty = todos.getOr(2, Todo.empty());

todos.watch().listen((event) => print('${event.key} -> ${event.value}'));
```

That's the whole loop. Reads come straight off the in-memory cache, so they're synchronous.
Writes are lazy `Task`s you `run()` at the edge. And since you get the box from an `open`
factory, holding one means it's already open. There's no init step to forget.

## 🧰 The box families

Here's the good part: every family has the **same surface**, so you learn it once and it
carries everywhere. The shape, in short:

- Absence is always `Option` / `TaskOption`, never `null` and never a magic default.
- Effects are always `Task`s. Nothing touches disk until you `.run()`, so pipelines compose first
  and fire once.
- `watch` is typed, and `close()` / `deleteFromDisk()` are terminal (reacquire, don't reuse).

<details>
<summary>📋 <b>The full method table</b> (KeyedBox shown, the others mirror it)</summary>

|                                                     | `KeyedBox<T, K>`              | `LazyKeyedBox<T, K>`              |
|-----------------------------------------------------|-------------------------------|-----------------------------------|
| `get(key)`                                          | `Option<T>`                   | `TaskOption<T>`                   |
| `getOr(key, fallback)`                              | `T`                           | `Task<T>`                         |
| `values`                                            | `Iterable<T>`                 | `Task<List<T>>`                   |
| `keys` / `contains` / `length`                      | sync                          | sync, after first open            |
| `put` / `putAll` / `delete` / `deleteAll` / `clear` | `Task<Unit>`                  | `Task<Unit>`                      |
| `putAllBy(values, {keyOf})`                         | `Task<Unit>`                  | `Task<Unit>`                      |
| `update(key, fn, {ifAbsent})`                       | `Task<T>`                     | `Task<T>`                         |
| `watch({key})`                                      | `Stream<TypedBoxEvent<T, K>>` | `Stream<LazyTypedBoxEvent<T, K>>` |
| `flush` / `compact` / `close` / `deleteFromDisk`    | `Task<Unit>`                  | `Task<Unit>`                      |

Watch is typed on both axes: an eager delete event still carries the value that was removed, and a
lazy event carries an `Option<T>` that's `None` on deletes, because a lazy box holds no value to
hand back.

`putAllBy` is sugar for the common case where each value already carries its own key, so
`Map.fromIterables(values.map((v) => v.id), values)` at the call site becomes
`putAllBy(values, keyOf: (v) => v.id)`. It builds no intermediate map, which measures about
**74 ns per entry** cheaper (0.94x) than writing the map yourself. `DualKeyBox` takes the same shape
with 2 extractors (`primaryOf:` and `secondaryOf:`), and `ListBox` has `putAllGrouped`, which
collects a flat iterable into one stored list per key.

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

Hive reads a collection of a custom type back as `List<dynamic>`
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

- Lists you read out are **unmodifiable views**, and lists you put in are **copied**. Mutating your
  original afterwards never leaks into the box. `add` / `addAll` / `remove` are read-modify-writes,
  O(n) in the stored list.
- **Absent isn't the same as empty.** `get` keeps them apart, while `getOr` folds both to `[]` on
  purpose.
- **List semantics only:** order preserved, duplicates allowed. For no duplicates, there's
  [`SetBox`](#-setbox).
- **Nesting:** a list or set of `int`, `double` or `String` nests fine (lists of `bool` and
  `Uint8List` too), since hive keeps those typed. Anything else nested, a `List<Person>` say, trips
  a development assert when you open the box, because the cast only reaches the outer list. Model
  those as adapter-registered value types instead. Same goes for `SetBox`.
- `LazyListBox` is the same surface on the lazy axis.

</details>

### 🧺 SetBox

A set of values per key, no duplicates. Members of a team, a user's favourites.

<details>
<summary>Telling elements apart, and add vs upsert</summary>

After a restart hive hands back fresh objects, so a plain set can't tell that 2 copies are the same
member. `idOf` tells it:

```dart
final teams = await SetBox.open<Member, String>(
  'team_members',
  idOf: (member) => member.id,
).run();

await teams.put('core', [Member(1, 'Ada'), Member(2, 'Grace')]).run(); // first one per id wins
await teams.add('core', Member(1, 'Ada L.')).run(); // id 1 is stored, so 'Ada' stays
await teams.upsert('core', Member(1, 'Ada L.')).run(); // replaces 'Ada' where she sits
await teams.remove('core', Member(2, 'Grace')).run(); // a fresh copy, matched by id

final core = teams.getOr('core'); // Set<Member>: unmodifiable view, empty when absent
```

Worth knowing:

- `idOf` returns a String, number, bool or enum. Elements of those types are their own id, so
  `SetBox.open<String, int>('favourites')` needs none. Any other element type without one trips an
  assert while wiring.
- Sets you read keep their **insertion order**, even after a restart. They're plain sets though, so
  `core.contains(...)` uses `==`, not `idOf`. Look an id up with `any` instead.
- Writes are copied, reads come back typed after a restart, and absent isn't empty, all like
  `ListBox`.
- `LazySetBox` is the same surface on the lazy axis.

</details>

### 📖 MapBox

A map of values per key. Prices per store, settings per user.

<details>
<summary>Merging, removing, and the keys a map can hold</summary>

Hive reads every map back as `Map<dynamic, dynamic>`, whatever it held, so a typed read after a
restart throws. `MapBox` restores both types at the read boundary:

```dart
final prices = await MapBox.open<String, double, int>('prices_by_store').run();

await prices.put(1, {'apple': 0.5, 'pear': 0.8}).run(); // stored as a private copy
await prices.addAll(1, {'pear': 0.9, 'plum': 1.2}).run(); // merges, so 'pear' is now 0.9
await prices.remove(1, 'apple').run(); // one entry out, the key stays

final storePrices = prices.getOr(1); // Map<String, double>: unmodifiable view, empty when absent
```

Worth knowing:

- The box key comes last, like every family: `MapBox<String, double, int>` holds a
  `Map<String, double>` under each `int`.
- Inner keys are strings, numbers, bools or enums, the types sure to compare equal after a
  restart hands back fresh objects. Anything else trips an assert while wiring, so key by an id.
- An int key hive can't store exactly (some past 2^53) fails with an `ArgumentError`,
  [like a bad box key](#-safer-than-raw-hive-at-near-native-speed).
- `addAll` and `remove` follow `Map`: the incoming value wins, and removing an absent key or entry
  writes nothing. Each one rewrites the whole map, and an emptied map keeps its key.
- Maps keep their insertion order across a restart. Writes are copied, reads are unmodifiable,
  absent isn't empty, and nested values follow `ListBox`'s rule, all like the other collections.
- `LazyMapBox` is the same surface on the lazy axis.

</details>

### 🔗 DualKeyBox

2 natural dimensions to your data (user + day, row + column). Address it by both parts, query by
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
**bit-identical to the old `0.0.x` `.bitShift` scheme**, so those boxes read in place. The 2
codecs trade off measurably. [Codec choice](#-codec-choice) has the head-to-head. Rolling your own
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

Extend `BoxObserver` and override only the events you care about. `PrintingBoxObserver` is the
ready-made sink. 2 notes on the engine side: `hive_ce`'s own warnings stay on its global logging
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
- **Reads are where they split.** An eager get is ~1.1 to 1.4 µs from memory. A lazy get pays for
  a disk read at ~26 µs.

Open cost tracks file size on both axes (the 2 lines sit right on top of each other), while
reads are where they part ways:

![Box open time by box size: eager and lazy overlap, both rising with size](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/open_eager_vs_lazy.png)

![Per-read latency by box size on a log scale: eager reads from memory sit far below lazy reads from disk](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/read_eager_vs_lazy.png)

So reach for **eager** on hot, value-heavy-*read* boxes that fit comfortably in RAM, and **lazy**
on value-heavy boxes you read only now and then. Neither opens "instantly" at scale, and keys are
a RAM cost you pay regardless.

### 💥 When a record won't decode

An eager box decodes every value while it opens, so one record its adapter can't read stops the
whole box from opening. hive_ce won't skip it ([hive_ce#318](https://github.com/IO-Design-Team/hive_ce/issues/318)).
A lazy box decodes on read instead, and `values` throws an `UndecodableValueException` naming the
key.

Keep fields you add to a model after its first release nullable, since older records won't have
them. If a box already won't open, open it lazily, delete each key an `UndecodableValueException`
names, then `compact()`. The eager open works again after that.

## 🛡️ Safer than raw hive, at near-native speed

Release-mode `hive_ce` takes an out-of-range int key or an oversized String key without
complaint, then corrupts quietly: keys wrap into other slots, and an oversized String key can make
the whole box file unreadable on its next open. This package rejects exactly those keys with an
`ArgumentError` at the call site, before anything reaches disk.

Keys inside a map get the same care. hive keeps ints as 64-bit floats, so 2 int keys past 2^53
can come back from a restart as one entry. `MapBox` rejects any int key a float can't hold
exactly, before anything reaches disk.

### ⚡ What that costs

There is no single number, and any package that gives you one is quoting the surface that flattered
it. Wrapper cost depends on how expensive the thing being wrapped is, so it splits by surface:

| Surface                                                             | Wrapper cost                                                        | Read as                                                                  |
|---------------------------------------------------------------------|---------------------------------------------------------------------|--------------------------------------------------------------------------|
| `KeyedBox` / `SingleValueBox`, memory reads (get, contains, values) | 1 to 22 ns per op                                                   | free                                                                     |
| Any effect that reaches disk (put, delete, lazy get)                | 300 to 700 ns per op, 2 to 4%                                       | free, disk dominates                                                     |
| `ListBox` reads                                                     | ~290 ns per `get`, plus ~8 to 13 ns per element of a custom type    | 2.6x to 3.1x on one-element lists, 0.9x to 1.8x on thousand-element ones |
| Batch writes (`putAll`, `deleteAll`)                                | 1 to 21 ns per entry                                                | free                                                                     |
| Open time, keystore RAM, file size                                  | no measurable difference                                            | identical                                                                |
| `DualKeyBox` eager get                                              | 1.02x (+3 to +21 ns per op)                                         | free                                                                     |
| `DualKeyBox` `putAll`                                               | +45 to +85 ns per entry (int parts), +230 to +310 ns (String parts) | 1.09x to 1.36x by batch size, see below                                  |

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

Precision, honestly: repeated passes reproduce the *bands* above and the ordering, not 2
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
others. 8 variants of the same two-part encode, each changing exactly one thing from the one
above it:

![8 key-shape variants by ns per op: the 3 that route a generic-parameterised record through a checked parameter cost about 355 ns, every other shape sits near 15 ns](https://raw.githubusercontent.com/LahaLuhem/hive_box_manager/master/benchmark/reports/key_shape_attribution.png)

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
baseline is the code you would hand-write, and there are 2 of those. Against the version with a
`.cast<T>()` at the read boundary, `ListBox` costs the ~290 ns per `get` above. Per element it
depends on what hive hands back. A `List<String>` comes back typed and goes out without a cast, so
it costs less per element than the hand-roll. A custom type's elements are each checked once at the
read, which is what lets a wrong type fail there and name its key. Against the version without a
cast, your hand-roll is *faster and broken*: a stored `List<Person>` reads back as `List<dynamic>`
after a restart and the cast throws. Memory matches a correct hand-roll on every lane, reads
included, so the read view really is copy-free.

### ⚡ Codec choice

2 dual-key codecs ship, and they trade off like this:

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
isolate key cost), not through a hand-rolled stand-in. Web is unmeasured. Its ordering is assumed to
follow the VM. `StringCompositeDualCodec` is the safe default. Reach for `PackedIntDualCodec` when
these wins matter and both parts fit in 16 bits.

The table rows are the 100K slice of these curves, and the gap widens as boxes grow:

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
- **Nested collections** beyond the shapes hive keeps typed, on the value-codec seam.
- **A consumer fakes package** (in-memory façades for app tests) and Flutter companions (a
  `ValueListenable` adapter), as separate packages so the core stays pure Dart.

Deliberately **never** wrapped, because they fight the typed, codec-addressed key model:
auto-increment `add` / `addAll`, index-based `getAt` / `putAt` / `deleteAt` / `keyAt`, `toMap`,
and `valuesBetween`. Reach for a raw `hive_ce` box where those genuinely fit.

</details>
