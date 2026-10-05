# APPENDIX for `hive_box_manager`

Design rationale: the "why" behind decisions that the code and the hard rules alone don't explain.
Hard rules and workflow live in [`.ai/AGENTS.md`](./.ai/AGENTS.md), code style in
[`CODESTYLE.md`](./CODESTYLE.md). Each heading carries an explicit `<a id="…">` anchor. Link by
anchor, and keep anchors stable across renames.

The 1.0 sections below were distilled from the rewrite's decision register after the build
completed. The empirical claims (probe results, benchmark numbers) are pinned by
`test/integration/hive_ce_pins/` and reproducible via `benchmark/`.

<!-- TOC start -->

- [`AGENTS.md` and `CLAUDE.md` are symlinks into `.ai/`](#ai-files-symlinked)
- [Dependabot's PRs auto-merge through dartender](#dependabot-automerge)
- [Pure-Dart package, no Flutter dependency](#pure-dart-not-flutter)
- [The fpdart, no-null surface](#fpdart-surface)
- [Packaging: engine deps in core, adapters in companions](#packaging-core-and-companions)
- [SDK floor & dependency set](#sdk-floor)
- [1.0 scope: capabilities, not classes](#scope)
- [Empirical gates: probe first, architect second](#empirical-gates)
- [Core abstraction: engine + policies + thin façades](#core-abstraction)
- [The seam model](#seam-model)
- [Variant taxonomy & naming](#variant-taxonomy)
- [Key strategy: 2 codecs, tiered validation](#key-strategy)
- [Collection handling: cast at the read boundary](#collection-handling)
- [Observability: semantic observers, split watch events](#observability)
- [Absence & error semantics](#absence-and-errors)
- [Test tooling: BDD shape, pins, and doubles](#test-tooling)
- [Build phases & checkpoints](#build-phases)
- [Migration & risk posture](#migration-and-risks)
- [Resolved design decisions (index)](#open-design-decisions)

<!-- TOC end -->

<a id="ai-files-symlinked"></a>
## `AGENTS.md` and `CLAUDE.md` are symlinks into `.ai/`

The canonical files live in [`.ai/`](./.ai/). The repo-root `AGENTS.md` and `CLAUDE.md` are symlinks
to them. Keeping the sources in `.ai/` groups the agent-facing docs in one place while still letting
tools that look at the repo root (and humans) find them. `.gitignore` commits the `.ai/` targets and
ignores the root symlinks. `.pubignore` excludes both the symlinks and the targets so none of it
ships in the published tarball.

Relative links in the 2 `.ai/` files are written to resolve from the repo root (the symlink
location), because the root symlink is how agents and GitHub read them.

---

<a id="dependabot-automerge"></a>
## Dependabot's PRs auto-merge through dartender

Every Dependabot PR, majors included, auto-merges through the `Auto-merge` job in
[dartender](https://github.com/LahaLuhem/dartender)'s shared `ci.yml`. 2 things still bite here:

- **The rulesets are the load-bearing half.** Auto-merge only waits on required checks, so it's
  safe only while `master` requires `ci / ok`, `conventions / ok` and the browser check. Keep
  `required_signatures` out: GitHub's rebase-merge makes unsigned commits (`6d0d385` is the
  evidence), so that rule would block every merge.
- **A merge made with `GITHUB_TOKEN` starts no workflows,** so `master`'s push run is skipped for
  auto-merged PRs. The changelog App's token would start them, but don't swap it in: the App is on
  every ruleset's bypass list so it can commit `CHANGELOG.md`, and a bypass lets it merge past the
  required checks.

---

<a id="pure-dart-not-flutter"></a>
## Pure-Dart package, no Flutter dependency

`hive_box_manager` is storage logic over `hive_ce`, and `hive_ce` is itself pure Dart, so the wrapper
stays pure Dart too: no Flutter dependency, no `dart:io`, no platform channels in the package. That
keeps it usable in a Dart server, a CLI, a web app, and a Flutter app alike, which is the same set of
places Hive is used.

Anything that would need Flutter (a `ValueListenable` view over a box's change stream, a widget
binding) does not go here. It goes in a companion package (see
[packaging](#packaging-core-and-companions)). The one Flutter artefact in the repo is the `example/`
app, which is a separate package with its own pubspec and does not make the library depend on
Flutter.

---

<a id="fpdart-surface"></a>
## The fpdart, no-null surface

The package's first aim is a clean functional surface, chosen for 2 reasons. First, it removes a
whole class of caller-side bugs: a read either yields a value or an explicit `Option`, so "did this
key exist?" is answered by the type instead of a nullable that every caller has to remember to check.
Second, the maintainer's apps already lean heavily on [`fpdart`](https://pub.dev/packages/fpdart), so
a surface that hands back `Task` / `TaskOption` / `Option` drops straight into existing pipelines
instead of forcing an `await`-and-rewrap at every call site.

The concrete commitments:

- **No `null` and no bare `Future` on the public surface.** Absence is `Option` / `TaskOption`,
  and asynchrony is a lazy `Task`, not an eager `Future`. The one blessed nullable is the
  `watch({key})` filter: a toggle the consumer passes, never a value they receive.
- **Laziness is deliberate.** `Task` doesn't run until `.run()`, so a box call is a description
  of an effect the consumer schedules, not an effect fired the moment the method returns. This is
  what lets reads and writes compose before anything touches the box.
- **Absence-first reads.** `get` returns `Option` / `TaskOption`. `getOr(key, fallback)` is sugar
  over it. The 0.0.x `defaultValue`-at-construction died because a box-level default conflates
  "give me something usable" with "is it there?" at every read site. The fallback now travels with
  the one call that wants it.

The full method-level shape is in
[`CODESTYLE.md#manager-contract`](./CODESTYLE.md#manager-contract).

---

<a id="packaging-core-and-companions"></a>
## Packaging: engine deps in core, adapters in companions

In Dart, dependencies are declared per package, not per library: the moment any file in the package
imports something, that dependency lands in every consumer's resolution and lockfile, even one who
touches a single box type. Tree-shaking drops unused *code*, not the dependency-graph entry. So the
decision turns on *what a dependency is for*.

- **Engine and paradigm dependencies live in core.** `hive_ce` is the storage engine the whole
  package wraps, and `fpdart` is the surface paradigm every façade speaks. Both are load-bearing,
  pure-Dart, and web-safe, so they belong in core. `meta` rides along for annotations, and
  `collection` for collection helpers.
- **Adapter dependencies go in companions.** Anything that adapts the façades to another ecosystem
  is genuinely opt-in and must never burden core: a Flutter binding, a `riverpod` / `bloc` glue
  layer, a codec for a specific serialisation. Each becomes its own package depending on core plus
  its one integration dependency.

Companions are built when actually needed, as their own repositories, matching the maintainer's other
packages.

---

<a id="sdk-floor"></a>
## SDK floor & dependency set

The floor lives in `pubspec.yaml`'s `sdk:` constraint. It came up from 3.9 for the 1.0 rewrite in 3
steps: 3.10 for static dot shorthands (a CODESTYLE idiom), 3.12 for private named parameters
(`Foo({required this._bar})`), and 3.13 for primary constructors, which superseded that spelling and
now declare the constructor-assigned fields on every façade, both engines, and both watch events
([`CODESTYLE.md#class-structure`](./CODESTYLE.md#class-structure)). One floor serves consumers and
contributors alike, the test toolchain (`test`, `build_runner`) flooring below the package. 1.0 was
the sanctioned breaking release, so the bump rode it, and since a floor can only be raised without a
breaking change, any further bump is recorded here.

The runtime dependencies are `hive_ce`, `fpdart`, `meta` and `collection`, and `pubspec.yaml` carries
the constraints. `hive_ce` is floored at the version every behaviour pin was taken against, though
≥2.12 is the *contractual* part, because that is where non-null delete-event values on the eager axis
arrive. Flutter's SDK constrains `meta` and `collection` too, so neither floor goes above what
Flutter stable accepts, or Flutter apps can't resolve. Discovered live with `meta`, back when Flutter
pinned it exactly.

---

<a id="scope"></a>
## 1.0 scope: capabilities, not classes

1.0 was scoped as a capability list (typed CRUD on both axes, a single-value box, collections per
key, composite keys with reverse queries, typed watch, encryption pass-through, per-instance
observability, full lifecycle) rather than a class list, so the taxonomy stayed free until the
architecture was settled. 2 scope calls deserve their reasoning on record:

- **Web is a supported, tested platform from 1.0.** Key encoding is persisted data, so shipping a
  web-unsafe encoding would have made adding web later a data-breaking change, the most expensive
  kind. CI runs the browser suite on chrome under dart2js *and* dart2wasm.
- **Deferred things are additive on proven seams.** The inverted-index reverse query, IsolatedHive
  / BoxCollection wrapping, a migration helper API, and the raw-hive conveniences that fight the
  typed key model (auto-increment `add`, index-based access, `toMap`, `valuesBetween`) are out of
  1.0, listed in the README's Roadmap, and each has a named seam it plugs into without breaking
  API.

---

<a id="empirical-gates"></a>
## Empirical gates: probe first, architect second

The 0.0.x design baked in beliefs about hive that turned out false or unproven (negative-key
handling, collection reads, "bitwise beats math", memory folklore). The rewrite inverted that:
7 probes ran against live `hive_ce` before any architecture leaned on the answers, with
decision rules pre-registered so the data could not be rationalised after the fact. The probes'
findings are pinned as tests (`test/integration/hive_ce_pins/`), so an engine upgrade that shifts
any of them fails loudly. Highlights that shaped the design: release-mode hive validates **no**
keys at write (its only guard is assert-stripped), disk reads reify collections of custom types as
`List<dynamic>`, lazy delete events carry no value while eager ones do, and
open time is O(file) on *both* axes. The benchmark harness that decided the key strategy lives on
in `benchmark/` as regression tooling.

---

<a id="core-abstraction"></a>
## Core abstraction: engine + policies + thin façades

CRUD is written exactly once per synchronicity axis, in 2 private engines. Everything that
varies enters as an injected policy (key codec, value codec, observer), and the public façades
are thin delegations that configure an engine and narrow the surface. A façade *cannot*
reimplement CRUD because it owns none. That covers read-modify-writes too. A façade hands the
engine's `update` or `edit` a function rather than chaining its own read and write, so a fix to
what happens between the two lands in one place. The rejected alternatives: a refined inheritance
family (the 0.0.x failure: the eager/lazy axis multiplies through every variant and template seams
re-fork), extension types (stateless, so no memoised open, and not implementable for consumer
fakes), and free functions (abandons CRUD-for-free).

Lifecycle is its own internal core. **Eager façades cannot exist unopened**: acquisition is a
`Task`-returning static `open`, so sync reads are always legal by construction. **Lazy façades
construct synchronously and auto-open single-flight** on the first effect (a memoised future,
reset by a failed open so the next run retries), with `ensureInitialised()` as the compositional
warm-up. This makes the 0.0.x init-forgotten crash unrepresentable rather than unlikely. The one
carve-out: the lazy sync inspectors (`length`, `isEmpty`, `isNotEmpty`, `keys`, `contains`) need
the keystore, so before the first open they throw a `StateError` naming the fix: deterministic
and message-guided where 0.0.x gave a null cast at a distance. `close()` and `deleteFromDisk()`
are terminal on both axes, and closing a never-used lazy handle is a no-op that opens nothing yet
still poisons the handle.

---

<a id="seam-model"></a>
## The seam model

Policies are small strategy interfaces, never loose function pairs: the 0.0.x `.negative` encoder
packed with shift 15 while the shared decode assumed shift 16, a shipped drift bug that
paired-function seams made representable. One interface holding both directions makes that
unrepresentable.

Visibility is earned, not defaulted: a public seam is a semver commitment, so only seams with
concrete consumer value went public (`KeyCodec` / `DualKeyCodec` for custom key schemes,
`BoxObserver` for diagnostics). The value codec stays internal because it is the one place
consumers could launder `dynamic` back into the surface. The box provider and the query-index
strategy stay internal until a second implementation exists (IsolatedHive and the inverted index,
both 1.x). The query seam already carries write/delete hooks so the 1.x index plugs in without
touching the public surface: the scan strategy implements them as no-ops.

**A value codec restores a type hive loses. It never serialises.** That's the adapter's job, and
adapters are the consumer's. JSON settled it: as a codec it would parse on every eager read, where an
adapter parses once at open.

---

<a id="variant-taxonomy"></a>
## Variant taxonomy & naming

6 shapes × 2 synchronicities = 12 `interface class` façades: `KeyedBox`, `SingleValueBox`,
`ListBox`, `SetBox`, `MapBox`, `DualKeyBox`, each with a `Lazy` twin. The names say what you
hold and mirror hive's own `Box` / `LazyBox` split. The 0.0.x `Manager` suffix died because the
1.0 types are a different contract, and same-name-changed-contract misleads migrators.
(`ListBox` rather than `CollectionBox` because hive_ce already exports the latter.)

The reverse query folds into the dual façades instead of being its own `Query*` family: the scan
is read-only and free unless called, and the separate 0.0.x query types only existed because of
inheritance wiring. `SingleValueBox` stays its own façade rather than a degenerate keyed box
because the no-argument `get()` *is* the variant. The eager collection variant exists (0.0.x was
lazy-only) because the memory folklore that forbade it was retired by measurement. Dual parts are
generic with `(int, int)` codecs shipped. Internally a dual box encodes both parts at the façade
and hands the shared engine a plain raw key, like every other family.

`MapBox` and `DualKeyBox` both find a value by 2 parts, and both stay because each is cheap where
the other pays. A map box keeps one record per key, read and written whole. A dual box keeps one
per pair, which makes single-entry writes and lookups by the second part cheap.
`MapBox<MK, MV, K>` puts the box key last, like every family.

---

<a id="key-strategy"></a>
## Key strategy: 2 codecs, tiered validation

Both dual codecs ship because the pre-registered benchmark rule fired: arithmetic int packing
beats the String composite by ≥1.5x on several end-to-end hot paths (eager gets, open, batch
writes, scans) and saves ~45% keystore RSS at 100K entries, but it carries a 16-bit-per-part
ceiling. So `StringCompositeDualCodec` is the safe default (full-range parts, negatives, no
ceilings) and `PackedIntDualCodec` is the documented opt-in, **bit-identical to the 0.0.x
`.bitShift` keys** (shift equals multiply for in-range parts), so legacy boxes read in place. The
0.0.x `.negative` encoder was not reshipped: the composite covers negatives natively, and that
encoder is the one that shipped the drift bug. Micro-benchmarks were treated as diagnostics only.
The decision rule pinned end-to-end paths, which is why "bitwise beats math" folklore died.

Validation is tiered, assert-first: construction wiring asserts (codec defaulting, part domains
on the opt-in codec, the types inside a collection), preconditions hive itself throws for get **no
wrapper check at all** (tier 3), and 2 **release-mode** gates, both on the write path:

- **The raw-key gate.** Release-mode hive_ce silently corrupts on out-of-range int keys and
  structurally destroys the box file on oversized String keys (its only guard is assert-stripped).
  Cost: 2 comparisons and a byte-length check against a ~10 µs write.
- **The exact-int gate on `MapBox`'s inner keys.** hive keeps ints as 64-bit floats, so 2 inner
  keys past 2^53 that a float can't tell apart come back from a reopen as one entry, pinned on the
  VM and dart2wasm. Cost: a pass over the inner keys, only when their type can hold an int.

Both carve-outs are earned by measurement, not caution. The keys that trip them are data-derived
(64-bit server ids, say), exactly the class development runs never see.

---

<a id="collection-handling"></a>
## Collection handling: cast at the read boundary

Hive reifies collections of custom types from disk as `List<dynamic>`, so a naive
`Box<List<Person>>` opens fine and throws on the first post-restart read. The probe established
that a thin `.cast<T>()` at the read boundary suffices, so the fix is an internal value codec, not
a `dynamic`-typed variant class (the 0.0.x approach, whose `dynamic` leak is part of why the rewrite
exists). Boxes open `Object?`-parameterised internally. `dynamic` never reaches the public surface.

The cast checks each element once, at the read, so a wrong one fails where the engine can name the
key, not wherever the view is next touched. An already-typed collection (written this session, or
one of hive's primitive lists) skips both the check and the cast, so the cost is one pass over a
custom-typed collection read from disk.

The aliasing contract closes the mutation hole from both directions: everything inward (`put`,
`putAll`, `update`'s returns) is materialised into a private fixed-length copy (hive rejects lazy
iterables at write anyway, so the copy is half-free), and everything outward is an unmodifiable
zero-copy **view**: eager gets alias hive's own cache, so a per-read defensive copy would tax the
hot path for a hole the view closes for free. This is the sanctioned scenario call under
CODESTYLE's unmodifiable-collections idiom. Nested collections stay out, because the outer cast
can't reach the inner ones, and one development assert refuses them while wiring, for list and set
elements and map values alike. The exception is the few shapes hive keeps typed, pinned as list
elements and as map values on the VM and both web compilers, so the assert can't drift from what
hive does.

Sets come back as `Set<dynamic>` and cast just as well. What they need on top is equality that
survives a restart. A set dedups with the element's `==`, and a read from disk builds fresh
objects, so a type that compares by identity never matches its stored copy. `SetBox` dedups by an
`idOf` instead (strings, numbers, bools and enums are their own id), and only on writes, which
keeps reads a zero-copy cast view:

- **Every write dedups the whole set**, not only what comes in, so an id stored twice some other way
  (raw hive, say) is down to its first element after the next write.
- **hive gets a plain `Set.of(...)`**, never one with custom equality. The eager cache hands back
  the written object until a restart, and a reopen builds a plain set, so a custom one would match
  by id before a restart and by `==` after. The price is that a set you read matches by `==`, the
  same as a list read from `ListBox`.
- **Merging writes are 2 named families.** `add` keeps a stored element with the same id, `upsert`
  replaces it where it sits. A `shouldOverwrite` flag lost, since a name says what happens at the
  call site and a 3rd policy would break a bool.
- **The asserts are development-only.** Without `idOf` a set box falls back to `==` and still
  works, where a box with no key codec can't work at all.

Maps come back as `Map<dynamic, dynamic>` whatever they hold, primitives included, and cast the
same way, keys and values checked in one pass. Their inner keys have the set's problem with no
`idOf` to lean on:

- **Inner keys are strings, numbers, bools or enums**, the types sure to compare equal after a
  restart. A map finds keys by `==`, and the type alone can't say whether a custom class compares
  by value or by identity, so a development assert refuses it and the map gets keyed by an id. It
  depends only on the type, so it fires on every development run, which is why an assert is enough.
- **hive gets a plain `Map.of(...)`**, for the same reason sets get a plain `Set.of(...)`.
- **Entry helpers follow `Map`**, since the names promise its behaviour: `addAll` lets the incoming
  value win and `remove` takes one entry out. Like the siblings, an emptied map keeps its key.

---

<a id="observability"></a>
## Observability: semantic observers, split watch events

Diagnostics follow the maintainer's cross-package observer convention: an `abstract base class`
`BoxObserver` with one no-op method per semantic event, extended and partially overridden, passed
per instance at construction. `base` (extend, never implement) diverges from the façades'
`interface class` deliberately: new events must land in minor releases, and nobody mocks our
observer: they write their own. The 0.0.x global assign-once callback died because it made
per-box attribution and testing miserable. Dispatch is direct and synchronous with no event
objects: box operations are hot-path, and an unattached observer must cost exactly one null
check. `boxName` leads every signature so one observer instance serves a whole app. hive_ce's own
logging channel is bypassed, not wrapped: engine warnings are the engine's domain.

The typed watch surface splits by axis because the engine's truth splits: eager delete events
carry the just-deleted value (hive serves it from cache, pinned), so `TypedBoxEvent.value` is
non-null even on deletes. A lazy box holds no values, so its deletes cannot carry one, and
`LazyTypedBoxEvent.value` is an `Option` with `deleted` derived from it. Pretending otherwise on
the lazy axis would have meant either lying (a sentinel) or a null: both banned.

---

<a id="absence-and-errors"></a>
## Absence & error semantics

The error channel is `Task`, not `TaskEither`: everything that can fail at runtime (engine
`HiveError`s, IO, the corruption gate) is fix-your-code / fix-your-disk class, and hive provides
no typed failure taxonomy worth an `Either` (string-matching its messages would be brittle).
Failures propagate as thrown errors inside the task with a documented throw taxonomy per method.
Consumers lift to `TaskEither.tryCatch` where they want values. Precondition violations (the
corruption gate, a missing codec) throw **synchronously at call time**, before the task exists:
fail at the site, not at `.run()`.

Reads are absence-first: `get` returns `Option` / `TaskOption`, `getOr` is sugar, and there is no
`tryGet` twin because the primary read *is* the absence-shaped one. Queries return plain,
possibly-empty lists, never `Option`: the 0.0.x `None`-on-no-matches conflation of "absent" with
"empty result" died, and `ListBox` keeps the same distinction between an absent key (`None`)
and a stored empty list (`Some(empty)`). Effects are `Task<Unit>` on both axes. Reads are sync
only where the eager cache makes them free.

---

<a id="test-tooling"></a>
## Test tooling: BDD shape, pins, and doubles

Suites are BDD-shaped (`Feature` / `Scenario` / `Scenario Outline` with parameters grouped in
named example tables) via a thin zero-dependency vocabulary copied from the maintainer's `minted`
package: the value is the shape, which forces naming the system under test, not a framework.
`bdd_framework` itself is Flutter-only, so it serves the example app's suites instead. Mocks are
generated (mockito + build_runner, committed because CI runs no codegen). Hand-written doubles
are reserved for the 2 seams where *stateful* behaviour is the point (the in-memory box fakes,
the recording observer), and a growing custom-fake count is treated as a design smell.

3 tagged lanes: `unit` (fast, in-memory), `integration` (real hive_ce on temp dirs), and
`browser` (chrome, dart2js + dart2wasm). The hive_ce behaviour pins are the load-bearing lane:
they encode everything the probes discovered, so the `hive_ce` caret can stay open, because an
engine release that shifts pinned semantics fails the suite instead of silently invalidating the
wrapper's contracts. The wrapper-overhead benchmark lane (`benchmark/`) holds the façades to raw
hive across 14 operations, and the measured numbers live in the README.

The aim was originally written as a flat "within 5% of raw", and measuring it properly showed that
target is malformed rather than met or missed. A percentage is only meaningful when the operation
being wrapped costs enough to be a denominator: a same-slot `SingleValueBox.get` is ~13 ns of raw
hive, so the `Option` allocation alone reads +89% while costing +11 ns, and no amount of optimising
would move that percentage anywhere useful. The aim is now two-currency: **tens of nanoseconds per
op on the memory paths, single-digit percent on anything that reaches disk**, with the per-op
figure authoritative wherever the 2 disagree. `DualKeyBox`'s eager get used to be the one surface
that genuinely missed, at 1.4x to 1.8x raw. That turned out not to be the record allocation or the
double dispatch, both of which are free: it was a `(K1, K2)` record parameter typed from the
adapter's own type parameters, costing ~350 ns per call on a subtype check. Encoding at the façade
removed the adapter and the cost with it (#14). `benchmark/key_shape_bench.dart` keeps the
attribution reproducible.

---

<a id="build-phases"></a>
## Build phases & checkpoints

The rewrite ran as 6 linear phases (teardown + truth pins → core internals → keyed façades →
single-value + iterable → dual + query → example + docs), each ending at a full-stop checkpoint:
diff summary, verification evidence, an explicit not-verified list, and maintainer review +
commit before the next phase started. Truth-pins-first de-risked everything after (the
architecture leaned only on pinned facts), and façade phases were sized to reviewable commits.
The protocol's one iron rule: plan-vs-reality divergences stop the build for an explicit decision
rather than being improvised around. The handful that occurred (a lazy-close rider the engine
missed, the `meta` floor colliding with Flutter's pin, an eager-get overhead regression) are
recorded in the relevant sections above.

---

<a id="migration-and-risks"></a>
## Migration & risk posture

Migration is document-only in 1.0 ([MIGRATION.md](./MIGRATION.md)): data compatibility was mostly
free by design (same box names and frames, the single-value slot key kept, packed keys
bit-identical to `.bitShift`), so a helper API would mostly wrap a one-shot loop the recipe shows
anyway. The one incompatible case (`.negative` dual boxes) gets a shim-codec recipe. Post-publish
rollback is **forward-fix**, never retraction: pub.dev reserves retracted versions for 7
days, and 0.0.8 stays installable forever via pinning. The `hive_ce` caret stays open with the
pin suite standing guard, which trades a rare loud CI failure for never shipping a stale engine
constraint.

---

<a id="open-design-decisions"></a>
## Resolved design decisions (index)

Every decision this section used to hold open is now made and argued above. The anchor stays for
old links. The mapping:

- the override-hook engine → [core abstraction](#core-abstraction) and [the seam model](#seam-model)
- the composite-key strategy → [key strategy](#key-strategy)
- collection handling → [cast at the read boundary](#collection-handling)
- logging → [observability](#observability)
- the parked branch experiments → [migration & risk posture](#migration-and-risks) (dispositions:
  lazy auto-init adopted strengthened, the multi-box index deferred to 1.x on the query seam, the
  hashCode-key idea rejected as a cautionary dead-end, the example branch superseded by `example/`)
- web support → [scope](#scope)
- test tooling → [its own section](#test-tooling)
