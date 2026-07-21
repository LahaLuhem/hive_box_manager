# AGENTS.md for `hive_box_manager`

Tool-agnostic brief for any coding agent (Copilot, Cursor, Codex, Claude Code, …) working in
this package. Claude-Code-specific guidance lives in [CLAUDE.md](./CLAUDE.md).

> **Setup phase.** This package is being rewritten from scratch for a breaking `1.0` on cleaner,
> more modular ground; the internal design is not settled yet. Sections that depend on the redo's
> decisions are marked **TODO (design pass)**. The *conventions* here are binding now; the
> *specifics* they defer are pending. Full background: `~/Desktop/manager-revamp/`.

## Project goal

A developer-experience wrapper over [`hive_ce`](https://pub.dev/packages/hive_ce) (the community
Hive fork; docs at <https://docs.hive.isar.community>), giving Hive's `Box` / `LazyBox` a typed,
functional surface. It adds no storage engine of its own. Four aims:

- **fpdart-first surface.** Reads and writes hand back lazy [`fpdart`](https://pub.dev/packages/fpdart)
  `Task` / `TaskOption` / `Option`, never a bare `Future` or `null`. Absence is an `Option`.
- **CRUD for free.** The per-box get / put / upsert / delete / clear boilerplate consumers usually
  hand-write ships as ready-made "Manager" types.
- **Purpose-built box variants.** Managers for specific shapes (single-value, collection-valued,
  dual-index, reverse-queryable), each adding semantic ergonomics over raw Hive.
- **Hive's performance, kept.** Raw speed is `hive_ce`'s headline; the wrapper must not trade it away.

Pure Dart, so it works in Flutter apps, Dart servers, and CLIs alike. `hive_ce` is the storage
engine; `fpdart` is the paradigm. Rationale:
[`APPENDIX.md#pure-dart-not-flutter`](./APPENDIX.md#pure-dart-not-flutter),
[`APPENDIX.md#fpdart-surface`](./APPENDIX.md#fpdart-surface).

## Stack

- **Dart ≥ 3.12** (constraint in `pubspec.yaml`; SDK channel pinned in `.fvmrc`), one floor for
  consumers and contributors alike (the test toolchain floors at 3.11, inside the package floor).
  Rationale and history: [`APPENDIX.md#sdk-floor`](./APPENDIX.md#sdk-floor).
- **`dart test`** for tests; **`dart --no-version-check analyze .`** for pedantic static analysis
  (pedantic mode is intentional). No Flutter dependency in the package, no platform channels. The
  `example/` app is Flutter and carries its own pubspec; its CI is wired separately once it lands.
- **`dependency_validator`** guards the dependency set; `dart_dependency_validator.yaml` scopes it
  to the published surface and skips the example.
- **Container-based linters** (`shellcheck` for shell, `actionlint` for workflows, `rumdl` for
  Markdown, `ryl` for YAML) run from the [`linterpol`](https://github.com/LahaLuhem/linterpol)
  Docker image, not local installs, so only Docker (plus `jq`) is needed. The check set and image
  tag live in one manifest, [`.github/lint-checks.json`](./.github/lint-checks.json); `repo.yml`
  fans a CI matrix over it and `scripts/release.sh`'s preflight loops the same file, so the two
  can't drift. **Adding a linter is one entry in that manifest.** Per-tool config tuned to the repo
  lives in `.rumdl.toml` and `.yamllint.yaml`.
- **CHANGELOG and the `version:` field are owned by [`scripts/release.sh`](./scripts/release.sh)**
  (via `cider`). Do not run `cider` by hand and do not edit `CHANGELOG.md` or `version:` directly.
  The `cider:` block in `pubspec.yaml` is static config (URLs, link templates) and is hand-editable.
- **Published to pub.dev.** `.pubignore` controls the tarball; `.editorconfig` is the source of
  truth for text-file conventions (line width 100, LF, UTF-8).

## Repo layout

```text
hive_box_manager/
├── lib/
│   ├── hive_box_manager.dart       Public entry; `export 'src/…'` only
│   └── src/                        Manager implementations (internal grouping: TODO design pass)
├── test/                           `dart test` units; mirrors lib/src/
├── example/                        Flutter demo app (own pubspec; CI wired when it lands)
├── analysis_options.yaml           Strict-mode + opinionated lints
├── dart_dependency_validator.yaml  Scopes dependency_validator (excludes example/)
├── pubspec.yaml                    Deps + cider config + topics
├── .pubignore                      Files excluded from `pub publish`
├── .fvmrc / .editorconfig          Local SDK pin / text-file formatting
├── CHANGELOG.md                    Pipeline-owned; appears on pub.dev
├── README.md                       pub.dev landing page
├── APPENDIX.md                     Design rationale (anchor-keyed)
├── CODESTYLE.md                    Library-package code style
└── .ai/                            This file + CLAUDE.md (symlinked to repo root)
```

The public API stays flat: `hive_box_manager.dart` re-exports every Manager, so moving code inside
`lib/src/` is never a breaking change as long as the re-exports hold. The internal grouping under
`lib/src/` is being reworked in the redo, so it is deliberately left unspecified here (**TODO
design pass**).

## Hard rules

1. **The Manager contract is the package's identity.** Every Manager wraps a Hive box behind the
   same functional surface: reads return `Task` / `TaskOption` / `Option` (never a bare `Future` or
   `null`), writes return `Task<Unit>`, and genuine absence is an `Option`, never a null or a magic
   sentinel. The precise contract (the method set, the eager-vs-lazy split, how `defaultValue` and
   the `tryGet` family relate) is settled in the redo. Full spec:
   [`CODESTYLE.md#manager-contract`](./CODESTYLE.md#manager-contract). **TODO design pass.**
2. **The public API lives only in `lib/hive_box_manager.dart`**, which re-exports from `lib/src/`.
   Don't make users import `package:hive_box_manager/src/…`. Shared internals stay in `lib/src/`.
3. **No `null` in the public surface.** Absence is `Option` / `TaskOption`; laziness is `Task` over
   an eager `Future`. This is aim #1, not a preference.
4. **No `dynamic` escape hatches.** `strict-casts`, `strict-inference`, `strict-raw-types` are all
   on. This one carries scar tissue: the pre-1.0 collection box leaked `dynamic` through the class
   hierarchy to dodge a Hive limitation, and removing exactly that is part of why the redo exists.
   Never launder a type through `dynamic` or `as`.
5. **No `print()` in library code.** `avoid_print` is a warning in `analysis_options.yaml`.
6. **Public symbols carry `///` dartdoc** explaining the guarantee and the semantics (eager vs
   lazy, how keys are handled), not the mechanical *what*. `public_member_api_docs` is on.
7. **Pure Dart, dependency-light core.** `hive_ce` (the storage engine) and `fpdart` (the surface
   paradigm) are the load-bearing core dependencies; every other dependency is a promise to all
   downstream users. Flutter-specific adapters (a `ValueListenable` view, a widget binding) go in
   companion packages, never in core. See
   [`APPENDIX.md#packaging-core-and-companions`](./APPENDIX.md#packaging-core-and-companions).
8. **Semver, strictly.** Any change to a public signature, a deletion, or a behavioural change of a
   documented contract is breaking. `cider` enforces the version-bump discipline. (The `1.0`
   rewrite is itself the one sanctioned wholesale break.)
9. **`CHANGELOG.md` is bot-owned. Do not edit any section, including `## Unreleased`.** Release
   headers are written by [`scripts/release.sh`](./scripts/release.sh); the `## Unreleased` buffer
   is appended to by [`.github/workflows/changelog.yml`](./.github/workflows/changelog.yml) from the
   merged PR title (governed by its `sem-*` label). Same prohibition on the `version:` field.

## PR conventions

Enforced by [`.github/workflows/pr-conventions.yml`](./.github/workflows/pr-conventions.yml).

- **Branch name**: `<type>/#<issue>-<slug>`, with `<type>` one of `feature`, `bugfix`, `chore`,
  `refactor`, `acceptance-test-issues`, `hotfix`. Example: `feature/#12-lazy-auto-init`.
- **Exactly one `sem-*` label per PR.** Selects the changelog category for the post-merge
  automation:

  | Label           | Cider type   | When to use                                    |
  |-----------------|--------------|------------------------------------------------|
  | `sem-add`       | `added`      | New public symbol / type                       |
  | `sem-change`    | `changed`    | Behavioural or signature change                |
  | `sem-deprecate` | `deprecated` | Public symbol marked for future removal        |
  | `sem-remove`    | `removed`    | Previously-public symbol dropped               |
  | `sem-bugfix`    | `fixed`      | Defect repair, no signature change             |
  | `sem-security`  | `security`   | Security-relevant fix                          |
  | `sem-skip`      | (skip)       | Internal-only change (CI, docs, tests, …)      |

  The PR title becomes the changelog line verbatim; phrase it as a release-note bullet.
- **PR body must not be empty**, **no merge commits in the PR range** (rebase to integrate `main`),
  **commit subjects ≤ 82 characters**.

## Style

Full guide: [`CODESTYLE.md`](./CODESTYLE.md). The lint posture is deliberately strict. Top rules to
keep in working memory:

- Type-annotate every public symbol; `final` by default for fields and locals; constrain generics
  to `<T extends Object>` so `null` / `dynamic` can't sneak into `T`.
- Nullability is explicit and rare: prefer `Option` to `T?` on the public surface, and never `as T`
  a nullable.
- 100-column line width; blank lines separate logical chunks within a method.
- No magic numbers in `lib/` code.
- Public symbols carry `///` dartdoc explaining *why* and *what guarantee*.
- British spelling in prose and identifiers, except names fixed by the SDK or a dependency
  (`toJson`, `compareTo`, `hashCode`).

## Guidelines for any AI agent

- **Always ask before making technical choices.** When a task admits more than one reasonable
  approach (a variant's policy hooks, the key-encoding strategy, whether a symbol is public, core
  vs companion, adding a dependency), stop and ask: present the options with trade-offs, say which
  you'd pick and why, then wait. Small choices compound.
- **Mark recommendations with `★`.** Prefix your preferred option so the user can scan and reply by
  echoing or overriding (e.g. "★ for 1-4, change 5 to B").
- **Document new user-facing features in the README** in the same change. Rationale and trade-offs
  go in `APPENDIX.md`; the README is the user-facing entry point.
- **Read `analysis_options.yaml` before writing code.** The lint posture is far stricter than the
  Dart default; code that fails lint won't pass review.
- **Surface semver implications loudly.** If a change touches anything re-exported from
  `lib/hive_box_manager.dart`, call out whether it's patch / minor / major before the diff lands.
- **Verify Hive's real behaviour; don't code to assumptions about it.** The pre-1.0 design baked in
  several beliefs about `hive_ce`'s limits (key types, negative-number keys, dataset-size ceilings,
  reading collections of custom types) that turned out false or merely unproven. Before building on
  "Hive can't do X", confirm it against the current `hive_ce` and its docs, and record the finding.
- **Prefer an existing package over a custom solution.** Before hand-rolling, look for a package
  that already solves it and wrap it. Vet the candidate before adopting: pure Dart and web-safe,
  permissive licence, and currently maintained, not just download count.
- **Refactor first when a change needs a better shape.** Do the enabling, behaviour-preserving
  refactor as its own step before building on top. Public-API breakage is semver-significant and
  slow to walk back once published, so surface the refactor and get sign-off before anything that
  touches the public API or adds a dependency.
- **The user manages git state; some tracked files won't show in `git status`.** The user may mark
  tracked files so their local edits are hidden from `git status` (typically
  `git update-index --skip-worktree` / `--assume-unchanged`). They are tracked, not gitignored, so
  a file you just edited can be genuinely changed on disk yet absent from `git status` and from
  `dart pub publish --dry-run`'s modified-files list. Don't try to re-stage or "fix" it: the user
  handles staging and committing. Trust the file contents you wrote, not `git status`.
