---
name: testing-and-verifying
description: Decides what to test and verify for a change in OpenSky and how to run it
  cheaply - picking the test plan from the diff, the quick rerun and package loops, compile
  checks across targets, real-data and render verification, and what to report. Use before
  running any test, build check, or verification, and before pushing.
---

# Testing and verifying

No automatic step runs the tests or builds locally. CI runs the whole unit plan on every
push to a pull request, draft included, so the local job is the quick evidence for the
change at hand, and the commit's `Tests:` section records it. Aim for evidence proportional
to risk: enough that you would bet the change works, no more.
The mechanics behind every command below are in `docs/testing.md`.

## One build per batch of edits

Every build or test run costs minutes of wall time on this machine, and only two builds run at
a time machine-wide (the build slots). So do not build after each file. Make every edit the
change needs, then run one check, read the result, fix everything it reports, and run again.
A session that builds after each edit spends its whole time waiting.

## Pick what to run from the diff

Start from `git diff --stat main...` and ask what could break, including code the diff did
not touch but that calls into it. Reasonable defaults, not rules:

| Change | Evidence |
| --- | --- |
| Docs, skills, Markdown only | `make check` |
| Makefile or `tools/` script | `make check`, then run the changed target or script once |
| Parser | New or updated synthetic-fixture tests, `make test-package T='OpenSkyFormatsESMTests/Suite'`, then `make test-unit PLAN=Formats` |
| Math routine | New or updated tests, `make test-package T='Target/Suite'` for the suites that cover it |
| Engine logic in one subsystem | `make test-unit PLAN=<layer>` for its layer (`Engine`, `Features`, or `App`), narrowed with `T=` while iterating |
| Shared types, `ShaderTypes.h`, project or `Config/` files, file moves between `OpenSky/` and a package module | `make build-app`, `make build-cli`, or `make build-tests` for the products the change reaches, then `make test-unit` |
| Rendering or shaders | `make test-unit PLAN=GPU`, plus an offscreen render the user can look at (`probing-real-game-data` skill); a green build does not prove a triangle appeared |
| Behavior that only shows on the real install | `make test-real T='Class/method()'`, one run per affected test |
| App UI | `building-app-ui` skill and `make build-app`; `make test-ui T='Suite/test()'` only for a UI test you added or whose control path changed (UI tests, below) |
| A performance claim or a per-frame loop to speed up | `make profile` before and after, Release build (`docs/testing.md`, Profiling); one issue per finding |
| Milestone acceptance | `make health`, `make test-real ALL=1`, `make test-ui`, and the acceptance record (format in `docs/tools/sidebar-acceptance.md`) in the closing PR. A milestone about load or frame time adds `make launch-sample` on the installed Release app |

The whole unit plan (`make test-unit PLAN=UnitTests`) and the sanitizers run in CI: the
unit plan on every push, the sanitizers and `make health` weekly. Do not run them locally
before a push; push and read `gh pr checks <n> --watch`.

Find the suites for a file with `grep -rl 'TypeName' Tests`. Suite names follow the type
under test (`BSAArchive` is covered by `BSAArchiveTests`). The plans and what each one builds
are in `Tests/AGENTS.md`.

A behavior change without a test that would have failed before it is unverified: write the
test first, watch it fail, then fix.

## Run it cheaply

The loops, from cheapest up:

1. `make compile` while fixing compile errors in package modules: `swift build` of the
   changed modules and their dependents, without Xcode.
2. `make test-package T='Target[/Suite[/test()]]'` for one package test target: `swift test`,
   no Xcode, no app. The first run compiles every package test target; later runs are
   incremental.
3. `make test-unit PLAN=<plan> [T=...]` builds and runs one plan through xcodebuild. `Quick`
   (the default) is every package bundle without the slow and GPU tests; `Formats`,
   `Engine`, `Features`, and `App` are one layer each; `GPU` is the GPU tag; `UnitTests` is
   everything. A plan builds only its bundles, so pick the smallest one that holds the
   suite.
4. `make test-rerun PLAN=<plan> [T=...]` reruns the plan as last built, without the build
   system. Use it to rerun after reading a failure, not after an edit: it warns when a
   source changed since the build.

Rules that hold across all four:

- `T='Target/Suite'` runs a whole suite; `T='Target/Suite/method()'` one test. A selector
  that matches nothing runs zero tests and still passes, so read the count.
- At the end, build only the Xcode products the change reaches, one target each:
  `make build-app`, `make build-cli`, and `make build-tests` (every bundle of a plan,
  `PLAN=UnitTests` by default, without running a test).
- `make coverage-floor` needs a run with `COVERAGE=1`; CI runs it on every push. Run it
  locally only when a parser change deletes tests or adds untested branches.
- After a failure, `make test-report` names the failing tests and messages, and shows
  time per tag. Do not hand-parse `.xcresult` JSON.
- Every plan sets a time allowance. A test that fails on it is a hang to fix, not a
  limit to raise: a raised limit hides the next hang too.

## Long runs

These commands build, so the background-shell and one-`xcodebuild` rules in the root
`AGENTS.md` apply to them: every `make test-*` and `make build-*`, `make health`,
`make install`, and `git push`.

- Start the command itself in the background, not with `> file` redirection, and wait for
  the completion notification. Do not `cat` the task output, `sleep`, or loop on a log
  before it arrives; a hook blocks `sleep`. Each check is one more turn, and each turn
  re-reads the whole context.
- The output already lists each error once, with repository paths. Read it from the
  notification. Open the transcript only when the output says errors were not shown.
- A build waits when both build slots are busy or another build uses its checkout, and says
  so. That wait is the plan working; do not start a second build to get around it.
- The build removes stale module copies itself and builds once more when a failed build
  left new ones (`docs/tools/build-system.md`). Do not delete `.swiftmodule` folders by
  hand.

## UI tests

`make test-ui` is the slowest run here. Each UI test launches and drives the app for about
15 to 25 s, so the whole plan takes many minutes after the build. It also takes over the
screen while the user may be working.

- Run it only when the change can break what a UI test checks: a new or changed UI test, or
  a changed sidebar control or accessibility id that a UI test uses. Then run only those
  tests with `T='Suite/test()'`.
- Do not run it as a routine check for engine, parser, rendering, tooling, or docs changes.
  The unit tests and the `make build-*` targets cover those. Write `test-ui not run: no UI test
  path changed` in the `Tests:` section.
- Milestone acceptance is the one place where the whole plan runs.

## Real-data runs

These guard the machine and are not optional:

- Real-data tests go through `make test-real` only, with `PERF=1` for the perf gates. It runs
  under the memory watchdog; a raw `xcodebuild` against the install once ran to 30 GB and locked the
  machine.
- `make test-real` runs the smoke set, the suites tagged `.smoke`. `ALL=1` runs every
  real-data test, for a milestone acceptance. Iterate with `T=...` on one test, and rerun
  it only after a change that could alter the result.
- A perf gate carries the `.perf` tag; `make test-real PERF=1` runs every one, built optimized.
- Captures and probe output go under `.logs/` (root `AGENTS.md`, Legal & IP boundary).

## Flaky tests

A test that fails, then passes on the same code, is flaky. Do not rerun it until it passes,
and never add a retry: both hide a real bug. `make test-unit T='Target/Suite/test()' N=100`
shows it fails sometimes. Then follow the rule in `Tests/AGENTS.md`: disable it with
`.disabled("flaky: #NNN")` and open a `bug` issue with the run directory.

## Report it

The commit body's `Tests:` section lists what ran and its result, and what was deliberately
not run and why (for example, `test-real not run: no real-data path changed`). It is a
record of the evidence, not a list to fill: one quick run that covers the change is a
complete entry. If something could not be verified, say so plainly rather than implying it
was.
