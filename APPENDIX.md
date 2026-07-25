# APPENDIX for `hive_box_manager`

Design rationale: the "why" behind decisions that the code and the hard rules alone don't explain.
Hard rules and workflow live in [`.ai/AGENTS.md`](./.ai/AGENTS.md); code style in
[`CODESTYLE.md`](./CODESTYLE.md). Each heading carries an explicit `<a id="…">` anchor; link by
anchor, and keep anchors stable across renames.

The 1.0 sections below were distilled from the rewrite's decision register after the build
completed; the empirical claims (probe results, benchmark numbers) are pinned by
`test/integration/hive_ce_pins/` and reproducible via `benchmark/`.

<!-- TOC start -->

- [`AGENTS.md` and `CLAUDE.md` are symlinks into `.ai/`](#ai-files-symlinked)
- [Pure-Dart package, no Flutter dependency](#pure-dart-not-flutter)
- [The fpdart, no-null surface](#fpdart-surface)
- [Packaging: engine deps in core, adapters in companions](#packaging-core-and-companions)
- [SDK floor & dependency set](#sdk-floor)
- [1.0 scope: capabilities, not classes](#scope)
- [Empirical gates: probe first, architect second](#empirical-gates)
- [Core abstraction: engine + policies + thin façades](#core-abstraction)
- [The seam model](#seam-model)
- [Variant taxonomy & naming](#variant-taxonomy)
- [Key strategy: two codecs, tiered validation](#key-strategy)
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

The canonical files live in [`.ai/`](./.ai/); the repo-root `AGENTS.md` and `CLAUDE.md` are symlinks
to them. Keeping the sources in `.ai/` groups the agent-facing docs in one place while still letting
tools that look at the repo root (and humans) find them. `.gitignore` commits the `.ai/` targets and
ignores the root symlinks; `.pubignore` excludes both the symlinks and the targets so none of it
ships in the published tarball.

Relative links in the two `.ai/` files are written to resolve from the repo root (the symlink
location), because the root symlink is how agents and GitHub read them.

---

<a id="pure-dart-not-flutter"></a>
## Pure-Dart package, no Flutter dependency

`hive_box_manager` is storage logic over `hive_ce`, and `hive_ce` is itself pure Dart, so the wrapper
stays pure Dart too: no Flutter dependency, no `dart:io`, no platform channels in the package. That
keeps it usable in a Dart server, a CLI, a web app, and a Flutter app alike, which is the same set of
places Hive is used.

Anything that would need Flutter (a `ValueListenable` view over a box's change stream, a widget
binding) does not go here; it goes in a companion package (see
[packaging](#packaging-core-and-companions)). The one Flutter artefact in the repo is the `example/`
app, which is a separate package with its own pubspec and does not make the library depend on
Flutter.

---

<a id="fpdart-surface"></a>
## The fpdart, no-null surface

The package's first aim is a clean functional surface, chosen for two reasons. First, it removes a
whole class of caller-side bugs: a read either yields a value or an explicit `Option`, so "did this
key exist?" is answered by the type instead of a nullable that every caller has to remember to check.
Second, the maintainer's apps already lean heavily on [`fpdart`](https://pub.dev/packages/fpdart), so
a surface that hands back `Task` / `TaskOption` / `Option` drops straight into existing pipelines
instead of forcing an `await`-and-rewrap at every call site.

The concrete commitments:

- **No `null` and no bare `Future` on the public surface.** Absence is `Option` / `TaskOption`;
  asynchrony is a lazy `Task`, not an eager `Future`. The one blessed nullable is the
  `watch({key})` filter: a toggle the consumer passes, never a value they receive.
- **Laziness is deliberate.** `Task` doesn't run until `.run()`, so a box call is a description
  of an effect the consumer schedules, not an effect fired the moment the method returns. This is
  what lets reads and writes compose before anything touches the box.
- **Absence-first reads.** `get` returns `Option` / `TaskOption`; `getOr(key, fallback)` is sugar
  over it. The 0.0.x `defaultValue`-at-construction died because a box-level default conflates
  "give me something usable" with "is it there?" at every read site; the fallback now travels with
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
  package wraps, and `fpdart` is the surface paradigm every façade speaks; both are load-bearing,
  pure-Dart, and web-safe, so they belong in core. `meta` rides along for annotations. That is the
  whole runtime set: `collection` was dropped for 1.0 (its one use disappeared with the new
  `putAll` shape) and returns only as a dev dependency for benchmark tooling.
- **Adapter dependencies go in companions.** Anything that adapts the façades to another ecosystem
  is genuinely opt-in and must never burden core: a Flutter binding, a `riverpod` / `bloc` glue
  layer, a codec for a specific serialisation. Each becomes its own package depending on core plus
  its one integration dependency.

Companions are built when actually needed, as their own repositories, matching the maintainer's other
packages.

---

<a id="sdk-floor"></a>
## SDK floor & dependency set

The floor is **Dart ≥ 3.12** (`pubspec.yaml`), raised from 3.9 for the 1.0 rewrite in two steps:
3.10 for static dot shorthands (a CODESTYLE idiom), then 3.12 for private named parameters
(`Foo({required this._bar})`), used across the internal constructors. One floor serves consumers
and contributors alike: the test toolchain (`test`, `build_runner`) floors at 3.11, inside the
package floor. 1.0 was the sanctioned breaking release, so the bump rode it; since a floor can only
be raised without a breaking change, any further bump is recorded here.

Runtime dependencies are exactly three: `hive_ce` (floored at `^2.19.3`, the version every
behaviour pin was taken against; ≥2.12 is *contractual*, because non-null delete-event values on
the eager axis arrive there), `fpdart`, and `meta`. One sizing note on `meta`: its floor matches
`hive_ce`'s (`^1.14.0`) rather than the registry's latest, because Flutter's SDK pins `meta`
exactly and a higher floor here locks every Flutter app out of the package: discovered live when
the example app first resolved against the core.

---

<a id="scope"></a>
## 1.0 scope: capabilities, not classes

1.0 was scoped as a capability list (typed CRUD on both axes, a single-value box, collections per
key, composite keys with reverse queries, typed watch, encryption pass-through, per-instance
observability, full lifecycle) rather than a class list, so the taxonomy stayed free until the
architecture was settled. Two scope calls deserve their reasoning on record:

- **Web is a supported, tested platform from 1.0.** Key encoding is persisted data; shipping a
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
seven probes ran against live `hive_ce` before any architecture leaned on the answers, with
decision rules pre-registered so the data could not be rationalised after the fact. The probes'
findings are pinned as tests (`test/integration/hive_ce_pins/`), so an engine upgrade that shifts
any of them fails loudly. Highlights that shaped the design: release-mode hive validates **no**
keys at write (its only guard is assert-stripped), disk reads reify collections as
`List<dynamic>` whatever was written, lazy delete events carry no value while eager ones do, and
open time is O(file) on *both* axes. The benchmark harness that decided the key strategy lives on
in `benchmark/` as regression tooling.

---

<a id="core-abstraction"></a>
## Core abstraction: engine + policies + thin façades

CRUD is written exactly once per synchronicity axis, in two private engines; everything that
varies enters as an injected policy (key codec, value codec, observer), and the eight public
façades are thin delegations that configure an engine and narrow the surface. A façade *cannot*
reimplement CRUD because it owns none. The rejected alternatives: a refined inheritance family
(the 0.0.x failure: the eager/lazy axis multiplies through every variant and template seams
re-fork), extension types (stateless, so no memoised open, and not implementable for consumer
fakes), and free functions (abandons CRUD-for-free).

Lifecycle is its own internal core. **Eager façades cannot exist unopened**: acquisition is a
`Task`-returning static `open`, so sync reads are always legal by construction. **Lazy façades
construct synchronously and auto-open single-flight** on the first effect (a memoised future;
a failed open resets it so the next run retries), with `ensureInitialised()` as the compositional
warm-up. This makes the 0.0.x init-forgotten crash unrepresentable rather than unlikely. The one
carve-out: the lazy sync inspectors (`length`, `isEmpty`, `isNotEmpty`, `keys`, `contains`) need
the keystore, so before the first open they throw a `StateError` naming the fix: deterministic
and message-guided where 0.0.x gave a null cast at a distance. `close()` and `deleteFromDisk()`
are terminal on both axes; closing a never-used lazy handle is a no-op that opens nothing yet
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
consumers could launder `dynamic` back into the surface; the box provider and the query-index
strategy stay internal until a second implementation exists (IsolatedHive and the inverted index,
both 1.x). The query seam already carries write/delete hooks so the 1.x index plugs in without
touching the public surface: the scan strategy simply implements them as no-ops.

---

<a id="variant-taxonomy"></a>
## Variant taxonomy & naming

Four shapes × two synchronicities = eight `interface class` façades: `KeyedBox`,
`SingleValueBox`, `ListBox`, `DualKeyBox`, each with a `Lazy` twin. The names say what you
hold and mirror hive's own `Box` / `LazyBox` split; the 0.0.x `Manager` suffix died because the
1.0 types are a different contract, and same-name-changed-contract misleads migrators.
(`ListBox` rather than `CollectionBox` because hive_ce already exports the latter.)

The reverse query folds into the dual façades instead of being its own `Query*` family: the scan
is read-only and free unless called, and the separate 0.0.x query types only existed because of
inheritance wiring. `SingleValueBox` stays its own façade rather than a degenerate keyed box
because the no-argument `get()` *is* the variant. The eager collection variant exists (0.0.x was
lazy-only) because the memory folklore that forbade it was retired by measurement. Dual parts are
generic with `(int, int)` codecs shipped; internally a dual box is the keyed engine over
`(K1, K2)` record keys, one small adapter away.

---

<a id="key-strategy"></a>
## Key strategy: two codecs, tiered validation

Both dual codecs ship because the pre-registered benchmark rule fired: arithmetic int packing
beats the String composite by ≥1.5x on several end-to-end hot paths (eager gets, open, batch
writes, scans) and saves ~45% keystore RSS at 100K entries, but it carries a 16-bit-per-part
ceiling. So `StringCompositeDualCodec` is the safe default (full-range parts, negatives, no
ceilings) and `PackedIntDualCodec` is the documented opt-in, **bit-identical to the 0.0.x
`.bitShift` keys** (shift equals multiply for in-range parts), so legacy boxes read in place. The
0.0.x `.negative` encoder was not reshipped: the composite covers negatives natively, and that
encoder is the one that shipped the drift bug. Micro-benchmarks were treated as diagnostics only;
the decision rule pinned end-to-end paths, which is why "bitwise beats math" folklore died.

Validation is tiered, assert-first: construction wiring asserts (codec defaulting, part domains
on the opt-in codec), preconditions hive itself throws for get **no wrapper check at all** (tier
3), and exactly one **release-mode** gate exists: the raw-key corruption gate on the write path.
That carve-out is earned by measurement, not caution: release-mode hive_ce silently corrupts on
out-of-range int keys and structurally destroys the box file on oversized String keys (its only
guard is assert-stripped), and the violating class of key (data-derived, e.g. 64-bit server ids)
is exactly the class development runs never see. Cost: two comparisons and a byte-length check
against a ~10 µs write.

---

<a id="collection-handling"></a>
## Collection handling: cast at the read boundary

Hive reifies collections from disk as `List<dynamic>` whatever the write-side element type, so a
naive `Box<List<Person>>` opens fine and throws on the first post-restart read. The probe
established that a thin `.cast<T>()` at the read boundary suffices, so the fix is an internal
value codec, not a `dynamic`-typed variant class (the 0.0.x approach, whose `dynamic` leak is
part of why the rewrite exists). Boxes open `Object?`-parameterised internally; `dynamic` never
reaches the public surface.

The aliasing contract closes the mutation hole from both directions: everything inward (`put`,
`putAll`, `update`'s returns) is materialised into a private fixed-length copy (hive rejects lazy
iterables at write anyway, so the copy is half-free), and everything outward is an unmodifiable
zero-copy **view**: eager gets alias hive's own cache, so a per-read defensive copy would tax the
hot path for a hole the view closes for free. This is the sanctioned scenario call under
CODESTYLE's unmodifiable-collections idiom. List semantics only in 1.0: Sets, maps, and nested
collections are deferred to the value-codec seam because the outer cast cannot fix inner
reification.

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
non-null even on deletes; a lazy box holds no values, so its deletes cannot carry one, and
`LazyTypedBoxEvent.value` is an `Option` with `deleted` derived from it. Pretending otherwise on
the lazy axis would have meant either lying (a sentinel) or a null: both banned.

---

<a id="absence-and-errors"></a>
## Absence & error semantics

The error channel is `Task`, not `TaskEither`: everything that can fail at runtime (engine
`HiveError`s, IO, the corruption gate) is fix-your-code / fix-your-disk class, and hive provides
no typed failure taxonomy worth an `Either` (string-matching its messages would be brittle).
Failures propagate as thrown errors inside the task with a documented throw taxonomy per method;
consumers lift to `TaskEither.tryCatch` where they want values. Precondition violations (the
corruption gate, a missing codec) throw **synchronously at call time**, before the task exists:
fail at the site, not at `.run()`.

Reads are absence-first: `get` returns `Option` / `TaskOption`, `getOr` is sugar, and there is no
`tryGet` twin because the primary read *is* the absence-shaped one. Queries return plain,
possibly-empty lists, never `Option`: the 0.0.x `None`-on-no-matches conflation of "absent" with
"empty result" died, and `ListBox` keeps the same distinction between an absent key (`None`)
and a stored empty list (`Some(empty)`). Effects are `Task<Unit>` on both axes; reads are sync
only where the eager cache makes them free.

---

<a id="test-tooling"></a>
## Test tooling: BDD shape, pins, and doubles

Suites are BDD-shaped (`Feature` / `Scenario` / `Scenario Outline` with parameters grouped in
named example tables) via a thin zero-dependency vocabulary copied from the maintainer's `minted`
package: the value is the shape, which forces naming the system under test, not a framework.
`bdd_framework` itself is Flutter-only, so it serves the example app's suites instead. Mocks are
generated (mockito + build_runner, committed because CI runs no codegen); hand-written doubles
are reserved for the two seams where *stateful* behaviour is the point (the in-memory box fakes,
the recording observer), and a growing custom-fake count is treated as a design smell.

Three tagged lanes: `unit` (fast, in-memory), `integration` (real hive_ce on temp dirs), and
`browser` (chrome, dart2js + dart2wasm). The hive_ce behaviour pins are the load-bearing lane:
they encode everything the probes discovered, so the `hive_ce` caret can stay open, because an
engine release that shifts pinned semantics fails the suite instead of silently invalidating the
wrapper's contracts. The wrapper-overhead benchmark lane (`benchmark/`) holds the façades to
within 5% of raw hive on eager get / lazy get / put; the measured numbers live in the README.

---

<a id="build-phases"></a>
## Build phases & checkpoints

The rewrite ran as six linear phases (teardown + truth pins → core internals → keyed façades →
single-value + iterable → dual + query → example + docs), each ending at a full-stop checkpoint:
diff summary, verification evidence, an explicit not-verified list, and maintainer review +
commit before the next phase started. Truth-pins-first de-risked everything after (the
architecture leaned only on pinned facts), and façade phases were sized to reviewable commits.
The protocol's one iron rule: plan-vs-reality divergences stop the build for an explicit decision
rather than being improvised around; the handful that occurred (a lazy-close rider the engine
missed, the `meta` floor colliding with Flutter's pin, an eager-get overhead regression) are
recorded in the relevant sections above.

---

<a id="migration-and-risks"></a>
## Migration & risk posture

Migration is document-only in 1.0 ([MIGRATION.md](./MIGRATION.md)): data compatibility was mostly
free by design (same box names and frames, the single-value slot key kept, packed keys
bit-identical to `.bitShift`), so a helper API would mostly wrap a one-shot loop the recipe shows
anyway. The one incompatible case (`.negative` dual boxes) gets a shim-codec recipe. Post-publish
rollback is **forward-fix**, never retraction: pub.dev reserves retracted versions for seven
days, and 0.0.8 stays installable forever via pinning. The `hive_ce` caret stays open with the
pin suite standing guard, which trades a rare loud CI failure for never shipping a stale engine
constraint.

---

<a id="open-design-decisions"></a>
## Resolved design decisions (index)

Every decision this section used to hold open is now made and argued above; the anchor stays for
old links. The mapping: the override-hook engine → [core abstraction](#core-abstraction) and
[the seam model](#seam-model); the composite-key strategy → [key strategy](#key-strategy);
collection handling → [cast at the read boundary](#collection-handling); logging →
[observability](#observability); the parked branch experiments →
[migration & risk posture](#migration-and-risks) (dispositions: lazy auto-init adopted
strengthened, the multi-box index deferred to 1.x on the query seam, the hashCode-key idea
rejected as a cautionary dead-end, the example branch superseded by `example/`); web support →
[scope](#scope); test tooling → [its own section](#test-tooling).
