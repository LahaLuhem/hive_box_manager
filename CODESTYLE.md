Library-package code style. Project facts (goal, stack, repo layout, hard rules) live in
[`.ai/AGENTS.md`](./.ai/AGENTS.md); design rationale lives in [`APPENDIX.md`](./APPENDIX.md).

The lint posture is deliberately strict (see [`analysis_options.yaml`](./analysis_options.yaml)).
The house style values explicit types, no ambient mutability, small focused types, no `null` on the
public surface, and one consistent shape across every Manager in the package.

Each heading below carries an explicit `<a id="…">` anchor. Link by anchor, not by heading text, so
renames don't break callers.

> **Setup phase.** The package is being rewritten from scratch for a breaking `1.0`. The generic
> style rules here are binding now; sections tied to the not-yet-settled public API are marked
> **TODO (design pass)**.

<!-- TOC start -->

- [Type safety & nullability](#type-safety)
- [Naming](#naming)
- [Formatting](#formatting)
- [Constants & magic numbers](#constants)
- [Class structure](#class-structure)
- [The Manager contract](#manager-contract)
- [Idioms](#idioms)
- [Comments & dartdoc](#dartdoc)
- [DCM rules (applied by hand)](#dcm-rules)
- [Test style](#test-style)
- [Documentation conventions (Markdown)](#documentation-conventions)
- [Shell scripts](#shell-scripts)

<!-- TOC end -->

<a id="type-safety"></a>
## Type safety & nullability

- **Type-annotate every public symbol.** Inference is fine on locals (`omit_local_variable_types`
  is on); public surfaces are not the place to rely on it.
- **`final` by default for fields and locals.** `prefer_final_fields`, `prefer_final_locals`,
  `prefer_final_in_for_each` are all on. Parameters are not required to be `final`, consistent with
  `avoid_final_parameters` and `parameter_assignments` (which forbids the actual bad behaviour:
  mutating a parameter inside the body).
- **No `null` on the public surface; absence is `Option`.** This package's whole point is a
  no-null functional surface. The canonical "value can be missing" path is a `tryGet`-style method
  returning `Option` / `TaskOption`, not a nullable return. `cast_nullable_to_non_nullable` is on,
  so `as T` on a `T?` fails lint; never launder nullability that way. Reach for `T?` only in private
  code that immediately lifts it into an `Option`.
- **Constrain generic type parameters to `<T extends Object>` by default.** Unbounded `<T>` lets
  `null` and `dynamic` satisfy `T`, the same failure modes the no-null rule and the
  [`dynamic`-escape-hatch ban](./.ai/AGENTS.md#hard-rules) guard against elsewhere. Bind to `Object`
  so the type system enforces "some real value, not null". A stored value is always a real object;
  absence is an `Option`, never a `null` masquerading as `T`.

  ```dart
  // Prefer:
  class BoxManager<T extends Object, K extends Object> { … }
  // Over:
  class BoxManager<T, K> { … }
  ```

  Exception: when `T` flows directly into an external API that itself uses unbounded `<T>` and
  relies on `null` as a sentinel. Don't reach for it speculatively; bind by default, loosen only
  when a real call site demands it.
- **No Java ceremony.** No getter-only abstract base classes, no `AbstractFooFactory`, no
  interface-per-class. Use mixins, sealed classes, records, extension types, and enums where they
  add clarity, not weight.

The `dynamic`-escape-hatch ban and the `print()`-in-library ban are contracts, not style; they live
under [*Hard rules* in `.ai/AGENTS.md`](./.ai/AGENTS.md#hard-rules).

---

<a id="naming"></a>
## Naming

- **Capitalise standard acronyms as words in type names.** Effective-Dart and `camel_case_types`
  want `Id`, `Json`, not `ID` / `JSON`; two-letter acronyms stay capitalised (`IO`).
- **Expand abbreviations everywhere else.** In code, comments, docstrings, and messages, spell
  domain terms out (`primaryIndex`, not `pIdx`; `boxKey`, not `bk`). Widely-known initialisms in
  prose (HTTP, JSON) stay as-is.
- **Local variables carry a concise type-suffix.** A reader without IDE inlay-hints can't see an
  inferred type; the name does that work. When a domain type exists, the suffix is the type name
  (`storedValue`, not `v`; `encodedKey`, not `k`). Callback and comparator parameters are exempt and
  stay single-word (`value`, `index`, `(a, b)`); the call site already pins the type.

---

<a id="formatting"></a>
## Formatting

- **Wrap text-file content at 100 columns.** [`.editorconfig`](./.editorconfig) is authoritative;
  Markdown, Dart, and YAML share the cap. The formatter's `page_width: 100` in
  `analysis_options.yaml` matches it; keep them aligned if either moves.
- **Comments and docstrings wrap *roughly* around 100, never at 80.** The Dart formatter doesn't
  reflow `//` / `///` prose, so break lines near the 100 mark wherever the sentence reads best; a
  few characters over beats an awkward mid-phrase break. The "roughly" does **not** apply to
  filetypes a linter hard-caps (linterpol's `ryl` for YAML, `rumdl` for Markdown): there 100 is a
  real limit and lines must stay under it.
- **Blank lines separate logical chunks within a method.** Group the guard checks, the box
  operation, and the return with one blank line between groups, so a reader can scan past chunks
  they don't need.
- **Prefer expression bodies** (`prefer_expression_function_bodies`) and **single quotes**
  (`prefer_single_quotes`). A Manager method wrapping one box call is frequently one expression;
  write it as one.

---

<a id="constants"></a>
## Constants & magic numbers

- **No magic numbers in `lib/` code.** Pull constants to named `static const`s with a descriptive
  identifier. (The pre-1.0 dual-index encoder kept its `bitShift` / `bitMask` on a dedicated
  constants holder; that instinct is right, the encoding strategy itself is under review.)
- **Name "magical" values everywhere intent matters, tests and tooling included.** A value with a
  real-world name (an engine limit, a bit width, a precision boundary) gets that name; naming also
  guards the value against accidental edits. Hyper-parameters (iteration counts, sampling caps,
  seeds) get names too.
- **Derive related constants from one another** instead of repeating baked results, so they cannot
  drift apart: `partMask = partCeiling - 1` and `'b' * (hiveMaxStringKeyBytes + 1)`, not parallel
  literals.
- **Peg to a predefined constant when a fitting one exists**:
  `Duration.microsecondsPerMillisecond` over `1000`, `double.maxFinite` over its digits.
- **Keep a type's own constants on that type**, close to where they are read. Genuinely
  cross-cutting constants go in a shared internal under `lib/src/`. Before introducing a new
  constant, check whether a shared one already exists.

---

<a id="class-structure"></a>
## Class structure

- **Fields, then constructors, then other members.** A reader scans the state shape first, then how
  to construct it, then how to use it. Unnamed constructor first, then named / factory (matches
  `sort_unnamed_constructors_first`); static members after the instance members.
- **`assert` for dev-time errors; surface runtime failure functionally.** A constraint a caller can
  only violate during development (a private helper handed a bad index) belongs in `assert`:
  stripped in release, zero runtime cost. A genuine runtime outcome (a key isn't present, a box
  op could fail) is expressed through the return type (`Option` / `TaskOption`, or an `Either` /
  `TaskEither` where the failure carries information), not a thrown exception the caller has to
  remember to catch. Prefer init-list asserts (`prefer_asserts_in_initializer_lists`,
  `prefer_asserts_with_message` are on).
  - **Prefer `assert(condition, 'message')` over `throw` for precondition violations** wherever
    stripping in release is possible and correct. An assertion is the fix-your-code signal (Error
    territory), not a runtime outcome (Exception territory), and costs nothing in release builds.
    Reserve release-mode failure for gaps where an unchecked precondition would cause silent
    damage that development runs cannot be relied on to surface.
  - **Never duplicate a precondition failure the engine already throws for.** If `hive_ce` itself
    errors loudly (wrong-kind box reopen, unknown-type writes), the wrapper adds no pre-check; the
    engine's error is the surface. Wrapper checks exist only where the engine stays silent.
- **Immutable value objects override `toString`, `==`, `hashCode`.** Any small data type the
  package exposes (a typed box event, a key wrapper) returns `'ClassName(field: value, …)'` from
  `toString` and hand-writes structural equality. No `Equatable` dependency; a few honest lines.

---

<a id="manager-contract"></a>
## The Manager contract

The headline convention: every Manager presents the **same** functional surface, so a consumer
learns one shape and applies it across every box variant. Rationale:
[`APPENDIX.md#fpdart-surface`](./APPENDIX.md#fpdart-surface).

**Committed invariants** (binding now):

- **Reads return fpdart types, never a bare `Future` or `null`.** An eager read (box already in
  memory) returns the value directly; a lazy read returns a `Task<T>`. A read that can legitimately
  find nothing returns `Option<T>` (eager) or `TaskOption<T>` (lazy). `Task` is lazy: nothing runs
  until `.run()` at the call boundary.
- **Absence is `Option`, not `null` or a sentinel.** The `tryGet` family expresses "the key isn't
  there". A plain `get` backed by a `defaultValue` is a convenience for "give me something usable",
  never a way to smuggle a `null` back in.
- **Writes return `Task<Unit>`.** They are lazy and composable; `Unit` (not `void`) so they chain in
  fpdart pipelines.
- **`<T extends Object>` on every value / key generic.** A stored value is a real object; `null` is
  never a valid stored value. See [type safety](#type-safety).

**TODO (design pass).** The precise contract is settled during the redo and recorded here as it
lands: the exact method set per variant, the eager-vs-lazy split, how `defaultValue` relates to the
`tryGet` family, the box-variant taxonomy (single-value, collection, dual-index, reverse-query), and
the key-handling / encoding strategy. Until then, the invariants above are fixed and everything more
specific is pending. Background and the open questions: `~/Desktop/manager-revamp/`.

---

<a id="idioms"></a>
## Idioms

<a id="idioms-fpdart"></a>
### Compose in fpdart; run at the boundary

Build the pipeline with `map` / `flatMap` on `Task` / `TaskOption` / `Option`; call `.run()` (or
fold the `Option`) once, at the edge where the effect is actually needed. Don't `.run()` mid-pipeline
to pull a value out and drop back into imperative code. Return the lazy type from library methods and
let the consumer decide when to run it.

```dart
// Prefer: stays lazy, one run at the edge
box.tryGet(key).map((value) => value.trim());
// Over: eager await, imperative rejoin
final value = await box.tryGet(key).run(); // ... then branch by hand
```

<a id="idioms-unmodifiable-collections"></a>
### Unmodifiable collections: lock as much as the scenario allows

Expose collections as locked as possible; picking the mechanism is a scenario-based call, and a
purely defensive preference when neither matters:

- **Consumers should observe changes to the source?** Use `UnmodifiableListView(…)` (and kin): it
  wraps without copying, so the view follows the underlying list.
- **Otherwise, default to `List.unmodifiable(…)`** (and `Set` / `Map` equivalents): the
  constructor copies, so the snapshot is immune to anyone still holding the underlying list.
- **When another concrete constraint dominates**, let the scenario decide and record the reason at
  the site with a `//` comment. Example: a zero-copy view over a source that is never mutated in
  place (a box cache on a hot read path) locks the consumer out without paying a copy per read.

<a id="idioms-collection-literals"></a>
### Data pipelines over collection-`for` comprehensions

Prefer `iterable.map(…)` (and kin) over `[for (final a in iterable) …]`: the pipeline reads as a
clear step-by-step transformation of the data, chains naturally, and stays a *lazy* `Iterable`.
Keep it lazy when the result feeds another loop or transformation later; materialise (`toList()`,
a collection literal) only at the point where evaluation is immediately needed, with a `//` reason
when it isn't obvious (a timed window, a stateful generator, reuse across consumers). Set and map
comprehensions (`{for (…) key: value}`) stay acceptable exactly where a materialised set/map is
immediately consumed (a `putAll` batch, a set-shaped compare); anything longer-lived goes through
the pipeline. (Replaces the earlier comprehension-first guidance; maintainer call, 2026-07-21.)

<a id="idioms-functional-pipelines"></a>
### Functional pipelines over imperative loops for lookup and transform

When the code maps around data (find one, select many, transform, reduce), prefer a functional
pipeline (`firstWhereOrNull`, `where`, `map`, `fold`, `any` / `every`, several from
[`package:collection`](https://pub.dev/packages/collection)) over a hand-written `for` loop. The
pipeline reads as the data's journey; the loop hides it in accumulate-and-return bookkeeping. Stay
lazy: don't end a chain with a reflexive `.toList()`; leave it an `Iterable` and let the terminal
consumer drive evaluation. Do side effects with a plain `for` loop, never `forEach` with a closure
(`avoid_function_literals_in_foreach_calls`). `package:collection` is not a runtime dependency
(dropped for 1.0); add it as a dev dependency when tests or tooling genuinely need its utilities.

<a id="idioms-observers"></a>
### Observability: semantic event observers, not level-based loggers

Diagnostics follow the maintainer's cross-package observer convention (reference implementation:
`better_internet_connectivity_checker`'s `ConnectivityObserver`):

- An `abstract base class XObserver` with one `onXyz(…)` method per semantic domain event, every
  method a **no-op default body**, const constructor. Consumers extend and override only the
  events they care about. `base` (extend, not implement) so new events land in minor releases
  without breaking subclasses.
- A shipped `PrintingXObserver` sink forwarding events to `dart:developer`'s `log()` under a
  configurable logger `name` (DevTools-filterable), error events at level 900 (`package:logging`'s
  SEVERE scale, without the dependency). Never `print()` (`avoid_print`), never `debugPrint`
  (Flutter-only), never a logging package dependency.
- **Silent by default**: no observer attached unless the consumer passes one at construction.
  Dispatch is synchronous and guarded by a null check, so an unattached observer costs nothing on
  hot paths; document "keep overrides cheap, do expensive sink work asynchronously".

<a id="idioms-parts"></a>
### `part` / `part of` only when structurally needed

Legitimate uses: sealed-class cases across files (Dart requires the same library for sealed
subtypes) and code-generation outputs. Avoid it for general organisation; imports are explicit, and
parts leak `_private` symbols across files. (The pre-1.0 code leaned on `part` to share a base across
the dual-index managers; whether the redo keeps that is a design-pass call, not a default.)

<a id="idioms-dot-shorthands"></a>
### Static dot shorthands where the context type is known

Where the context type is known, drop the leading type name; the analyzer resolves the member from
the parameter, return, or variable type. Covers enum values in patterns and argument slots, and
named constructors / static factories in a return or context slot. Skip it where the context type
isn't obvious without re-reading.

---

<a id="dartdoc"></a>
## Comments & dartdoc

Public symbols carry `///` dartdoc explaining *why* and *what guarantee*, not the mechanical *what*:
the type already says that. `public_member_api_docs` is on (see
[hard rule 6 in `.ai/AGENTS.md`](./.ai/AGENTS.md#hard-rules)). For every Manager, document the
semantics a consumer can't read off the signature: eager vs lazy (does a read hit disk?), how keys
are handled, and what a `defaultValue` means for that method.

### `@docImport` for dartdoc-only references

When a file needs a symbol only for `[Name]` references in dartdoc, use Dart's dartdoc-only directive
rather than a real `import`; a regular import declares a runtime dependency and makes the import
graph lie.

```dart
/// @docImport 'package:hive_ce/hive.dart';
library;
```

---

<a id="dcm-rules"></a>
## DCM rules (applied by hand)

`dart analyze` does not run these, but the project treats them as non-negotiable:

- **`no-empty-block`**: every block must contain code or a `// TODO(handle): …` explaining the gap.
  Empty `catch` clauses are excused.
- **`newline-before-return`**: separate a block-final `return` from a preceding non-return statement
  with one blank line. Inline guards (`if (cond) return …;`) do not need it.
- **`prefer-commenting-analyzer-ignores`**: every `// ignore:` needs an adjacent `//` explanation
  (dartdoc `///` does not count).

---

<a id="test-style"></a>
## Test style

- **`package:test`, with `package:checks` for assertions** (`check(x).equals(…)`, `.isNull()`),
  matching the maintainer's other packages, not `package:matcher`'s `expect`. (`shouldly` is
  retired.)
- **Suites are BDD-shaped.** Tests read as `Feature:` / `Scenario:` / `Scenario Outline:` around
  a named system under test, with Given / When / Then flows. (Hyper-)parameters live in **one
  place**: named example tables (`Map<String, Row>` with record rows), one test per row, never
  literals scattered through test bodies. The vocabulary is the thin, zero-dependency
  `test/support/bdd.dart` copied from the `minted` package (`feature` / `scenario` /
  `scenarioOutline<Row>` over `package:test`); the value is the shape, not a framework.
  `bdd_framework` itself is Flutter-only, so it may appear in the Flutter `example/` app's
  tests, never in the pure-Dart core.
- **Mocks are generated (mockito + build_runner); custom fakes stay rare.** Generated mocks are
  reproducible and give the suite structure as the surface grows. Hand-write a double only when
  *stateful* behaviour is the point (an in-memory box seam, a recording observer), and treat a
  growing custom-fake count as a design smell to investigate, not a pattern to extend.
- **Mirror `lib/src/` in `test/`.**
- **Test against an in-memory box seam, not a real Hive box on disk.** The pre-1.0 dual-index tests
  injected a fake `LazyBox` through a `@visibleForTesting` seam; keep that pattern so unit tests stay
  fast and deterministic.
- **Cover the absence and failure paths, not just the happy path.** For a functional surface that
  means asserting `None` / empty `Option` where a key is missing, not only the found case. A
  positive-only suite hides the exact bugs a no-null surface is meant to prevent.

---

<a id="documentation-conventions"></a>
## Documentation conventions (Markdown)

- **APPENDIX.md is the source of truth for rationale.** Hard rules, pitfalls, and workflow stay in
  `.ai/AGENTS.md` and `.ai/CLAUDE.md`; the "why we do it this way" essays live in
  [`APPENDIX.md`](./APPENDIX.md).
- **Explicit `<a id="…">` anchors** sit above every APPENDIX and CODESTYLE heading. Link via the
  anchor, not the heading text. Anchor stability is load-bearing: when renaming a heading, keep the
  existing anchor, or `rg` the repo and update every caller in the same change.
- **Bare `dart` in command examples, never `fvm dart`.** FVM is a local implementation detail
  (`.fvmrc` pins the SDK). Docs stay tool-agnostic so external contributors aren't forced into FVM;
  scripts under `scripts/` handle the FVM-vs-PATH resolution themselves.
- **British spelling in prose and identifiers** (`normalise`, `behaviour`, `initialise`), with one
  carve-out: names fixed by the SDK or a dependency stay as they are (`toJson`, `compareTo`,
  `hashCode`, and Hive's own `Box` / `LazyBox` API).

---

<a id="shell-scripts"></a>
## Shell scripts

- **`shellcheck` is the lint contract** for `scripts/*.sh`, mirroring `dart analyze` for Dart. It
  runs from the [`linterpol`](https://github.com/LahaLuhem/linterpol) Docker image
  (`docker run --rm -v "$PWD:/work:ro" ghcr.io/lahaluhem/linterpol:latest shellcheck scripts/*.sh`),
  so the only local requirement is Docker (plus `jq`). Both `scripts/release.sh`'s preflight and
  [`.github/workflows/repo.yml`](./.github/workflows/repo.yml) enforce it; they read the check set
  (shellcheck, actionlint, rumdl, ryl) and the image tag from one manifest,
  [`.github/lint-checks.json`](./.github/lint-checks.json), so neither can drift.
- **Prefer `# shellcheck disable=SC<code>` + a one-line "why" over refactoring for simple cases.**
  Refactor when the warning points at a real bug; reach for the directive when the code is correct
  and ShellCheck is just over-conservative. Always pair the directive with a comment.
