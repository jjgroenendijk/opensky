---
type: Decision
title: Code-health automation
description: Which code-health checks OpenSky runs, where each one runs, and what it
  costs. Gates start at zero findings and use no baseline files.
tags: [decision, tooling, lint, code-quality]
---

# Code-health automation

This page lists the checks that keep the code healthy, where each runs, and why.
It replaces the old jscpd and Periphery gates. Those gates compared against checked-in
baseline files, and updating the baselines after each refactor cost too much.

## Rules for every check

- **Zero-start gates, no baseline.** A check becomes a gate only when it reports zero
  findings on `main`. There are no baseline files and no "known findings" lists. This is the ratchet-to-zero
  practice that SwiftLint, ESLint, and Go teams use when they add a rule to old code.
- **The cheapest place that works.** A check runs in `make lint` if it reads files
  only and takes about a second or less. A check that needs a build runs in its own
  `make` target. A check that needs GitHub runs there.
- **`make check` and CI mirror each other.** Every lint check has the same step in
  `ci.yml`, as AGENTS.md requires. The `Lint` job is the required check on `main`
  ([continuous integration](/tools/ci.md)).
- **No new suppression comments.** No `periphery:ignore` and no new `swiftlint:disable`.
  Fix the finding instead.

## The checks

"Lint" means `make lint` and a CI job. "Health" means `make health`, on demand.

| Check | Tool | Where | Cost |
| --- | --- | --- | --- |
| Duplicated code | jscpd, `make duplicates` | Lint | Under a second, whole tree |
| Unused code | Periphery, `make health` | Health | Index build plus about 1.5 min scan |
| Module graph (TMA) | `tools/lint/module-graph.sh` | Lint | Seconds, no build |
| Comment length | `tools/lint/comment-length.sh` | Lint | Under a second |
| File length | `tools/lint/file-length.sh`, `make file-length` | Lint, pre-commit hook | Under a second |
| No lint suppressions | `make no-suppressions` | Lint | Instant |
| New SwiftLint rules | SwiftLint | Lint | Part of the current lint |
| No new `GameViewController` extensions | SwiftLint `custom_rules` | Lint | Part of the current lint |
| Parser coverage floor | `llvm-cov`, `make coverage-floor` | After `make test-unit`, CI | Seconds |

## Duplicated code: jscpd

jscpd finds copied blocks of tokens. The settings stay as before: a clone counts at 100
tokens and 10 lines, exact matches only. It scans `Sources` and `Tests` together in well
under a second, so `make lint` runs it on the whole tree. A scan of only the changed files
would miss a copy of code that did not change.

PMD CPD was rejected because it needs a Java runtime. jscpd is one Homebrew binary.

## Unused code: Periphery, not `swiftlint analyze`

Both tools were tried against the tree.

- **Periphery** reads the index store that the compiler writes. It finds unused
  declarations, properties that are assigned but never read, unused imports, unused
  parameters, and redundant conformances.
- **`swiftlint analyze`** (`unused_declaration`, `unused_import`) needs the compiler log
  of a clean build. The normal build logs contain no `swiftc` command lines, because the
  compilation cache replays the build. So it needs its own uncached clean build on every
  run, and it covers only two of Periphery's checks.

Periphery wins: it covers more, and its index build is incremental after the first run.

The index build is uncached and goes into its own tree, `DerivedData-index/`, because a
build served from the compilation cache writes almost no index data. A separate tree also
means the build does not deadlock with a normal `xcodebuild` run. The scan covers the
app, the CLI, and every unit test target.

Settings:

- `retain_public: false`. The whole program is scanned together, so an unused public
  declaration is found like any other.
- `disable_redundant_public_analysis: true`. "Redundant public" reports a `public`
  declaration that no other module uses. In TMA, the Interface modules decide the
  public API, and the module-graph check guards it. This finding is style, not dead code.
- `retain_hashable_properties: true`. A stored property of an `Equatable` or `Hashable`
  type is read by the synthesized `==` and `hash(into:)`, which the index does not show.
  Example: the fields of a dictionary key such as `AmbienceKey`. Without this setting,
  Periphery reports them as assigned but never read.
- `retain_assign_only_property_types`. A property of one of these types only keeps an
  object alive. Nothing reads it, on purpose.
  - `FFmpegDecodeResources` holds ffmpeg objects until `deinit` frees them.
  - `NSWindowController` is the app delegate's only strong reference to the main window's
    controller.
  - `AcceptanceWorld`, `SceneCrimeWorld`, `SceneReferences`, `FakeWorldReferences` and
    `PapyrusWorldFixture.Session` are test fixtures. The runtime under test holds them
    weakly (`CasterRuntime.world`, `CrimeReporter.world`, `PapyrusWorldStateBridge.world`),
    so the fixture must hold them strongly.
- `retain_equatable_properties` stays off. Most panel snapshot types are `Equatable`, so
  this setting would hide dead snapshot fields. A test struct compared with `==` reads its
  fields in an assertion instead.
- **A decoded field counts as used when a test reads it.** Record fields that a
  `docs/formats/` page documents stay. With test targets in the scan, a parser test that
  checks the decoded value is a use. So a documented field needs a test, not a
  suppression comment. That is good practice anyway: every decoded field gets checked.
- **A skipped-record count counts as used when a test reads it.** A store that counts
  malformed records gets a test that feeds it one, like `AudioRecordStoreSkipTests`.

## Module graph

The rules, the layer list, and the exceptions are in
[The Modular Architecture](/decisions/modular-architecture.md).

## Comment length

The limit and the rules are in AGENTS.md. `make comment-blocks` and `make comment-apply`
help rewrite many blocks at once.

## File length

The limits are in AGENTS.md: a warning above 600 lines, a failure above 800. The check
reads every text file, not only Swift, because a long shader or script is as hard to
review as a long Swift file. It is the one check in a git hook, because a split is cheap
before the commit and expensive after review starts. The hook reads the staged content,
so a file trimmed but not staged still fails. CI runs it over the whole tree; `make lint`
runs it over the files the branch changed. A warning does not fail, so files between 600
and 800 lines can wait for their next real change.

## SwiftLint rules

Each candidate was run against the whole tree:

| Rule | Result | Decision |
| --- | --- | --- |
| `unavailable_function` | 0 findings | On |
| `no_extension_access_modifier` | 0 findings | On |
| `type_body_length` (default 250 lines) | 0 findings | On by default |
| `superfluous_disable_command` | 0 findings | On by default |
| `discouraged_optional_boolean` | Dozens of findings | Rejected |

`discouraged_optional_boolean` is rejected because a record parser needs three states for
an optional flag field: absent, false, and true. `Bool?` states that exactly.

`type_body_length` counts one declaration body only. A type split over many extension
files, like `GameViewController`, passes it. So a second rule is needed for that type.

## GameViewController extensions

`GameViewController` keeps only the view, input, the render loop, and the panel wiring, in
`GameViewController.swift` and `GameViewControllerPanels.swift`. A SwiftLint
`custom_rules` entry, `game_view_controller_extension`, forbids `extension
GameViewController` in any other file. The allowed file names are one regular expression
in `tools/lint/.swiftlint.yml`. It is a design rule for the future, not a list of old
findings.

## Lint suppressions

`make no-suppressions`, part of `make lint`, fails on any `swiftlint:disable` comment
under `Sources` or `Tests`.

## Test coverage

The unit plan measures the `OpenSky` app target and the package modules. `make
coverage-floor`, run after `make test-unit`, fails when an `OpenSkyFormats*` module is under
`COVERAGE_FLOOR` in the `Makefile`. The floor is the lowest module's value when it was
set, rounded down to a multiple of 5 percent: 83.07 % for `OpenSkyFormatsSWF` gave 80.
One floor for all, not one per module, leaves room for the GPU tests that skip on a CI
runner without Metal 4. CI runs the check after `make test-unit`.

The floor is only for the parsers. They read untrusted files, and a gap there can crash
the app. A floor for the whole codebase is not used. It pushes people to write tests that
execute code without checking anything.

## Not used

- **Security scanning and fuzzing** (CodeQL, gitleaks, libFuzzer). Out of scope for this
  project.
- **Dependabot.** Renovate covers the GitHub Actions, the Swift packages, and the CI tool
  pins in one weekly pull request, and Dependabot cannot read the tool pins
  ([CI](/tools/ci.md#dependency-updates)).
