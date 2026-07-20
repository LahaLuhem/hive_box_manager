# CLAUDE.md for `hive_box_manager`

Claude-Code-specific guidance. Project facts, stack, hard rules, and AI-agent guidelines live in
[AGENTS.md](./AGENTS.md); the full code-style guide lives in [`./CODESTYLE.md`](./CODESTYLE.md);
design rationale lives in [`./APPENDIX.md`](./APPENDIX.md). Read AGENTS.md and CODESTYLE.md first.

## Role & context

You're assisting with **hive_box_manager**: a pure-Dart, fpdart-style developer-experience wrapper
over `hive_ce` that gives Hive's boxes a typed functional surface (`Task` / `TaskOption` / `Option`,
no nulls), ready-made CRUD, and purpose-built box variants. It is being rewritten from scratch for
a breaking `1.0`, so expect greenfield work under settled conventions rather than incremental
patches. Treat the user as technical and direct. The package is on pub.dev, so changes are visible
to every downstream user; breakage is expensive and slow to walk back (unpublished versions stay
reserved for 7 days).

## Communication

- **Concise.** No "here's what I just did" recap; the diff speaks.
- **Explain the *why*** when recommending. The *what* is in the diff.
- Reference code as `file.dart:42` (markdown links if you can).
- Flag breaking-API or lint-violation implications loudly and early.

## Technical choices: always ask first

- **Do not silently pick between reasonable alternatives.** Whenever a task admits more than one
  defensible approach (a box variant's policy hooks, the key-encoding strategy, whether a helper
  belongs on the Manager or in a shared internal, whether a symbol is public, core vs companion,
  adding a dependency), **stop and ask.** List the options with trade-offs, say which you'd pick and
  why, then wait.
- **"Small" choices count.** The bar isn't "is this architecturally significant"; it's "could a
  reasonable maintainer disagree with my pick". If yes, ask.
- **Mark your recommendation with `★`** so the user can scan and reply by echoing or overriding.
- **Exception:** obvious single-answer fixes (typo, clear bug with one correct patch, lint error).
  Just do them.

## Tool preferences

- **Read / Edit / Grep / Glob** over `cat` / `sed` / `grep` / `find`. Always.
- **Bash** only for things without a dedicated tool: `dart`, `git`. The user's shell aliases `dart`
  to the toolchain serving the `.fvmrc` pin; invoke plain `dart`.
- **Lint with `dart --no-version-check analyze .`** (pedantic mode is the contract). Don't
  substitute plain `dart analyze` and ignore what it surfaces.
- **Agent tool** for wide / open-ended searches or to keep large output out of context.

## Scope awareness

- **Public-API edits** (anything in `lib/hive_box_manager.dart` or re-exported from it) are
  pub.dev-visible. Flag whether the change is patch / minor / major under semver before it lands.
  The functional surface (Task / Option, no null) *is* the public contract; don't erode it.
- **`lib/src/` edits** are private; refactor freely as long as the public re-exports stay stable.
- **`test/` edits** are local, no publish impact.
- **`analysis_options.yaml` edits** affect every file; surface lint-posture changes loudly and add
  a written reason in `APPENDIX.md`.
- **`pubspec.yaml` dependency edits** add to every downstream user's transitive closure; treat as
  public-API-class, and remember opinionated deps belong in companion packages, not core.

## Auto-memory conventions for this project

- **`project` memories**: scope / constraints the user states aloud (e.g. "ship 1.0 with these
  box types", "raising the SDK floor on date Y"). Convert relative dates to absolute.
- **`feedback` memories**: corrections and validated non-obvious choices. Include **Why** and
  **How to apply**.
- **`reference` memories**: external pointers (pub.dev page, the context7 project, `hive_ce` docs
  / issues, the `~/Desktop/manager-revamp/` overview). Not internal code paths, which live in
  AGENTS.md or are derivable from the repo.
- **Do NOT save** Dart file paths, lint-rule lists, or the API surface; all derivable from the repo
  or APPENDIX.md. Before acting on a memory, verify the named file / symbol still exists.

## Plan before editing when

- The change touches the public API (anything re-exported from `lib/hive_box_manager.dart`); even
  adding a new Manager or method affects semver and downstream users.
- You're adding or removing a dependency in `pubspec.yaml`.
- You're changing `analysis_options.yaml`; lint posture is project-wide and any toggle deserves a
  written reason in APPENDIX.

For a single-file, single-concern change inside `lib/src/`, just do it.

The release flow (`CHANGELOG.md`, `version:` in `pubspec.yaml`) is **not** in this list: both are
pipeline-owned (see *Forbidden* below). Don't plan or make a CHANGELOG edit or a version bump.

## Commit / PR etiquette

- **Never commit without being asked.** Not after a fix, not as a "checkpoint". Leave changes in
  the working tree; suggest a message, let the user land it.
- **Never push without being asked.** Especially not to `main`.
- **Never `--amend`** unless asked; create a new commit instead.
- **Never `--no-verify`**, **never `git add -A`**; stage named paths.
- When asked for a commit: show `git status` + `git diff`, draft the message, wait for approval.
  Match existing commit style (short imperative subject).

## Forbidden / confirm-first actions

- **Never** `dart pub publish`. Publishing is effectively one-way (pub.dev reserves the version for
  7 days after retraction). Releases go through `scripts/release.sh`, which the user runs manually
  (it pushes to `origin/main` and triggers publish). If the user wants a release, suggest
  `scripts/release.sh <bump>`; don't run it.
- **Never** run `cider` commands or manually edit `CHANGELOG.md` (including `## Unreleased`) or the
  `version:` field. Those are owned by `scripts/release.sh` and the changelog automation; manual
  edits get reordered or overwritten. The `cider:` block in `pubspec.yaml` is static config,
  hand-editable.
- **Never** edit `pubspec.lock` directly (it's `dart pub get`'s output).
- **Never** delete files under `.fvm/`, `.dart_tool/`, or `pubspec.lock` without approval.
- **Destructive git** (`reset --hard`, `push --force`, `branch -D`, `clean -fd`) → ask first.

## Definition of done

- `dart --no-version-check analyze .` clean (pedantic mode).
- `dart format --output=none --set-exit-if-changed .` clean.
- `dart test` green.
- New / changed Managers honour the [Manager contract](./CODESTYLE.md#manager-contract): the
  functional surface (`Task` / `TaskOption` / `Option`), no null, `Option` for genuine absence, and
  documented eager-vs-lazy semantics.
- DCM rules applied by hand (`dart analyze` doesn't run them): `no-empty-block`,
  `newline-before-return`, `prefer-commenting-analyzer-ignores`, plus blank lines segmenting
  logical chunks in methods.
- Lint clean via the linterpol image for whatever changed: `shellcheck` (shell), `actionlint`
  (workflows), `rumdl` (Markdown), `ryl` (YAML). The check set and per-tool config live in
  `.github/lint-checks.json`, `.rumdl.toml`, and `.yamllint.yaml`.
- `dart pub publish --dry-run` clean if the change is publish-relevant. Do not bump the version or
  edit the CHANGELOG to make it pass; `scripts/release.sh` owns those.
- Public API additions carry `///` dartdoc and are reflected in the README.
- Explicitly call out what you did NOT verify.
