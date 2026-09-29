---
type: Decision
title: Code-health automation
description: Which code-health checks OpenSky runs, where each one runs, what it
  costs, and which issue turns it on. Gates start at zero findings and use no baseline files.
tags: [decision, tooling, lint, code-quality]
---

# Code-health automation

This page lists the checks that keep the code healthy, where each runs, and why.
It replaces the old jscpd and Periphery gates. Those gates compared against checked-in
baseline files, and updating the baselines after each refactor cost too much.

## Rules for every check

- **Zero-start gates, no baseline.** A check becomes a gate only when it reports zero
  findings on `main`. Until then it runs in report mode: it prints findings and exits 0.
  There are no baseline files and no "known findings" lists. This is the ratchet-to-zero
  practice that SwiftLint, ESLint, and Go teams use when they add a rule to old code.
- **The cheapest place that works.** A check runs in the pre-commit hook if it reads
  files only and takes about a second or less. A check that needs a build runs in the
  pre-push hook or in a `make` target. A check that needs GitHub runs there.
- **Hooks and CI mirror each other.** Every hook check has the same step in `ci.yml`,
  as AGENTS.md requires. CI runs only on manual dispatch
  ([environment](/tools/environment.md)), so the hooks are the real gate.
- **No new suppression comments.** No `periphery:ignore` and no new `swiftlint:disable`.
  Fix the finding instead.

## The checks

"Pre-commit" means the pre-commit hook, `make lint`, and a Linux CI job (30.6). "Pre-push"
means the pre-push hook and `make health`. The last column names the issue that turns
the check on as a gate.

| Check | Tool | Where | Cost | Gate in |
| --- | --- | --- | --- | --- |
| Duplicated code | jscpd | Pre-commit | Under a second, whole tree | 30.39, after 30.20, 30.21, 30.23 |
| Unused code | Periphery | Pre-push | Index build plus about 1.5 min scan | 30.39, after 30.8 to 30.10 |
| Module graph (TMA) | `tools/lint/module-graph.sh` | Pre-commit | Seconds, no build | 30.5 (rules 4, 5: 30.22) |
| Comment length | `tools/lint/comment-length.sh` | Pre-commit | Under a second | 30.39, after 30.35 to 30.37 |
| No lint suppressions | `grep` in `make lint` | Pre-commit | Instant | 30.39, after 30.11 |
| New SwiftLint rules | SwiftLint | Pre-commit | Part of the current lint | 30.39 |
| No new `GameViewController` extensions | SwiftLint `custom_rules` | Pre-commit | Part of the current lint | 30.39, after 30.34 |
| Test coverage floor | `xccov`, `llvm-cov` | `make test-report`, Linux CI | Part of the test run | Report 30.38, floor 30.39 |

## Duplicated code: jscpd

jscpd finds copied blocks of tokens. The settings stay as before: a clone counts at 100
tokens and 10 lines, exact matches only. It scans `Sources` and `Tests` together in well
under a second, so it runs on the whole tree in the pre-commit hook whenever a Swift file
is staged. A scan of only the staged files would miss a copy of code that is not staged.

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

The pre-push hook runs Periphery only when the pushed commits change a Swift file.

Settings:

- `retain_public: false`. The whole program is scanned together, so an unused public
  declaration is found like any other.
- `disable_redundant_public_analysis: true`. "Redundant public" reports a `public`
  declaration that no other module uses. In TMA, the Interface modules decide the
  public API, and the module-graph check guards it. This finding is style, not dead code.
- **A decoded field counts as used when a test reads it.** 30.8 keeps record fields that a
  `docs/formats/` page documents. With test targets in the scan, a parser test that
  checks the decoded value is a use. So a documented field needs a test, not a
  suppression comment. That is good practice anyway: every decoded field gets checked.

## Module graph

30.5 owns this check and its decision page. It runs from `swift package dump-package` and
the `import` lines, with no build.

## Comment length

30.7 adds `make comment-length` in report mode. The limit and the rules are in AGENTS.md.

## SwiftLint rules

Each candidate was run against the whole tree:

| Rule | Result | Decision |
| --- | --- | --- |
| `unavailable_function` | 0 findings | Add in 30.39 |
| `no_extension_access_modifier` | 0 findings | Add in 30.39 |
| `type_body_length` (default 250 lines) | 0 findings | Add in 30.39 |
| `superfluous_disable_command` | 0 findings | Already on by default |
| `discouraged_optional_boolean` | Dozens of findings | Rejected |

`discouraged_optional_boolean` is rejected because a record parser needs three states for
an optional flag field: absent, false, and true. `Bool?` states that exactly.

`type_body_length` counts one declaration body only. A type split over many extension
files, like `GameViewController`, passes it. So a second rule is needed for that type.

## GameViewController extensions

After 30.34, `GameViewController` keeps only the view, input, the render loop, and the
panel wiring. 30.34 puts those into a fixed set of files named by role. Then a SwiftLint
`custom_rules` entry forbids `extension GameViewController` in any other file. The allowed
file names are one regular expression in `tools/lint/.swiftlint.yml`. It is a design rule
for the future, not a list of old findings. 30.12 adds the AGENTS.md rule first, so no new
extension files appear before the lint rule exists.

## Lint suppressions

After 30.11, `grep -rn "swiftlint:disable" Sources Tests` prints nothing. From 30.39,
`make lint` fails when it prints anything.

## Test coverage

`make test-report` already prints coverage from `xccov`. The test plans measure only the
`OpenSky` app target, so the package modules are not measured. 30.38 runs the format
module tests on Linux with `swift test --enable-code-coverage` and prints the coverage per
module. 30.39 sets a floor for the `OpenSkyFormats*` modules: the value measured then,
rounded down to a multiple of 5 percent.

The floor is only for the parsers. They read untrusted files, and a gap there can crash
the app. A floor for the whole codebase is not used. It pushes people to write tests that
execute code without checking anything.

## Not used

- **Security scanning and fuzzing** (CodeQL, gitleaks, libFuzzer). Out of scope for this
  project.
- **Dependabot.** There are no SwiftPM package dependencies. The vendored ffmpeg is
  pinned in `tools/vendor-ffmpeg.sh`, which Dependabot cannot read.
