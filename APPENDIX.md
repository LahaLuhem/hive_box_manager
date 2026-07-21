# APPENDIX for `hive_box_manager`

Design rationale: the "why" behind decisions that the code and the hard rules alone don't explain.
Hard rules and workflow live in [`.ai/AGENTS.md`](./.ai/AGENTS.md); code style in
[`CODESTYLE.md`](./CODESTYLE.md). Each heading carries an explicit `<a id="…">` anchor; link by
anchor, and keep anchors stable across renames.

> **Setup phase.** This package is being rewritten from scratch for a breaking `1.0`. The sections
> below are the decisions already settled; the design-pass decisions that the redo still owes are
> listed under [Open design decisions](#open-design-decisions) rather than argued here, because they
> haven't been made yet. The full pre-redo analysis (history, box taxonomy, the assumptions that
> proved shaky, the parked branch ideas) lives at `~/Desktop/manager-revamp/`.

<!-- TOC start -->

- [`AGENTS.md` and `CLAUDE.md` are symlinks into `.ai/`](#ai-files-symlinked)
- [Pure-Dart package, no Flutter dependency](#pure-dart-not-flutter)
- [The fpdart, no-null surface](#fpdart-surface)
- [Packaging: engine deps in core, adapters in companions](#packaging-core-and-companions)
- [SDK floor](#sdk-floor)
- [Open design decisions (the redo owes these)](#open-design-decisions)

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
a Manager that hands back `Task` / `TaskOption` / `Option` drops straight into existing pipelines
instead of forcing an `await`-and-rewrap at every call site.

The concrete commitments:

- **No `null` and no bare `Future` on the public surface.** Absence is `Option` / `TaskOption`;
  asynchrony is a lazy `Task`, not an eager `Future`.
- **Laziness is deliberate.** `Task` doesn't run until `.run()`, so a Manager call is a description
  of an effect the consumer schedules, not an effect fired the moment the method returns. This is
  what lets reads and writes compose before anything touches the box.
- **`defaultValue` is a convenience, not a nullability dodge.** A plain `get` can hand back a usable
  default; genuine "not present" is still expressed through the `tryGet` / `Option` path, so the two
  questions ("give me something" vs "is it there?") stay distinct.

The full method-level shape is in [`CODESTYLE.md#manager-contract`](./CODESTYLE.md#manager-contract),
and the precise per-variant API is a [design-pass decision](#open-design-decisions).

---

<a id="packaging-core-and-companions"></a>
## Packaging: engine deps in core, adapters in companions

In Dart, dependencies are declared per package, not per library: the moment any file in the package
imports something, that dependency lands in every consumer's resolution and lockfile, even one who
touches a single Manager. Tree-shaking drops unused *code*, not the dependency-graph entry. So the
decision turns on *what a dependency is for*.

- **Engine and paradigm dependencies live in core.** `hive_ce` is the storage engine the whole
  package wraps, and `fpdart` is the surface paradigm every Manager speaks; both are load-bearing,
  pure-Dart, and web-safe, so they belong in core. `collection` and `meta` are the usual light
  utilities.
- **Adapter dependencies go in companions.** Anything that adapts the Managers to another ecosystem
  is genuinely opt-in and must never burden core: a Flutter binding, a `riverpod` / `bloc` glue
  layer, a codec for a specific serialisation. Each becomes its own package depending on core plus
  its one integration dependency.

Companions are built when actually needed, as their own repositories, matching the maintainer's other
packages.

---

<a id="sdk-floor"></a>
## SDK floor

The floor is currently **Dart ≥ 3.12** (`pubspec.yaml`), raised from 3.9 for the 1.0 rewrite in two
steps: 3.10 for static dot shorthands (a CODESTYLE idiom), then 3.12 for private named parameters
(`Foo({required this._bar})`), now used across the internal constructors. One floor serves consumers
and contributors alike: the test toolchain (`test`, `build_runner`) floors at 3.11, inside the
package floor. Since a floor can only be raised without a breaking change, any further bump is
recorded here (it is breaking for anyone on the older SDK). The full 1.0 rationale lands with the
release docs pass.

---

<a id="open-design-decisions"></a>
## Open design decisions (the redo owes these)

These are the decisions the rewrite still has to make. They are listed, not argued, because the
choice hasn't been made; each becomes its own rationale section above once it lands. Full context,
tradeoffs, and the parked branch experiments are in `~/Desktop/manager-revamp/`.

- **The override-hook engine.** The north-star for the redo is a core where a variant (or a consumer)
  customises behaviour by overriding a policy hook, rather than inheriting and duplicating. The seams
  (encoder, key strategy, storage backend, logging) need designing before any box type is ported.
- **Composite-key strategy.** Whether to keep encoding two indices into one integer key (the pre-1.0
  bit-shift scheme, with its 16-bit-per-index ceiling and negative-number handling) or switch to a
  `String` composite key, which `hive_ce` supports and which lifts those limits. The int approach
  rested on unproven performance conjectures; benchmark before committing.
- **Collection-of-custom-types handling.** The pre-1.0 collection box leaked `dynamic` through the
  hierarchy to work around a `hive_ce` read limitation. The limitation is real, but a thinner cast or
  codec at the read boundary may replace the `dynamic`-typed variant.
- **Logging.** Move from the single assign-once global log callback to a per-instance logger injected
  at construction.
- **Branch experiments to fold in or drop.** Lazy-box auto-init (open on first use), the inverted-index
  "multi-box" reverse query for large datasets, and the hashCode-based primitive-key generalisation
  (a cautionary dead-end). See the overview doc.
- **Web support.** Decide whether web is a target; if so, the composite-key scheme needs explicit web
  testing (JS 32-bit bitwise semantics) or replacement.
- **Test tooling.** Settle the `package:test` + `package:checks` (+ fake box seam) shape for the new
  API; the pre-1.0 `shouldly` + `mockito` suite is replaced.
