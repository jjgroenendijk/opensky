---
name: testing-and-verifying
description: Decides what to test and verify for a change in OpenSky and how to run it
  cheaply - picking suites from the diff, the test targets, compile checks across targets,
  real-data and render verification, and what to report. Use before running any test,
  build check, or verification, and before pushing.
---

# Testing and verifying

No automatic step runs the tests or builds. What gets tested and scanned before a push is
your call, and the commit's `Tests:` section records it. Aim for evidence proportional to
risk: enough that you would bet the change works, no more.
The mechanics behind every command below are in `docs/testing.md`.

## Pick what to run from the diff

Start from `git diff --stat main...` and ask what could break, including code the diff did
not touch but that calls into it. Reasonable defaults, not rules:

| Change | Evidence |
| --- | --- |
| Docs, skills, Markdown only | `make check` |
| Makefile or `tools/` script | `make check`, then run the changed target or script once |
| Parser | New or updated synthetic-fixture tests, `make test-unit T='Suite'`, then `make test-parser` before pushing |
| Math routine | New or updated tests, `make test-unit T='Suite'` for the suites that cover it |
| Engine logic in one subsystem | `make test-unit T='Suite'` for its suites, then `make test-unit` (whole unit plan) once before pushing |
| Shared types, `ShaderTypes.h`, project or `Config/` files, file moves between `OpenSky/` and a package module | `make verify-build`, `make realdata-build`, then `make test-unit` |
| Rendering or shaders | `make test-gpu`, plus an offscreen render the user can look at (`probing-real-game-data` skill); a green build does not prove a triangle appeared |
| Behavior that only shows on the real install | `make test-real T='Class/method()'`, one run per affected test |
| App UI | `building-app-ui` skill and `make verify-build`; `make test-ui T='Suite/test()'` only for a UI test you added or whose control path changed (UI tests, below) |
| A performance claim or a per-frame loop to speed up | `make profile` before and after, Release build (`docs/testing.md`, Profiling); one issue per finding |
| Milestone acceptance | `make health`, `make test-real`, `make test-sanitize-thread`, `make test-sanitize-address`, `make test-ui`, and the acceptance record (format in `docs/tools/sidebar-acceptance.md`) in the closing PR |

Find the suites for a file with `grep -rl 'TypeName' Tests`.
A tag plan runs one kind of suite across every unit target: `make test-parser` or
`make test-gpu`. The tags and the rule for which a new suite must carry are in `Tests/AGENTS.md`;
`make lint-test-tags` checks them.
Suite names follow the type under test (`BSAArchive` is covered by `BSAArchiveTests`).

A behavior change without a test that would have failed before it is unverified: write the
test first, watch it fail, then fix.

## Run it cheaply

- Each kind of test has one target, `make test-<kind>`, and each is one plain
  `xcodebuild test` call on one test plan. Keep scripts out from between `make` and
  `xcodebuild`, so the plan and the native flags alone choose what runs.
- `make test-unit T='Suite'` runs a whole suite; `T='Suite/method()'` runs one test. A
  selector that matches nothing runs zero tests and still passes, so read the count.
- Every run pays the build-system start-up, about 15 s warm. Batch several edits into one
  run instead of rerunning after each edit.
- While fixing compile errors in package modules, loop on `make compile` (or
  `make compile M='OpenSkyWorld'`). It runs `swift build` on the changed modules and their
  dependents, without Xcode. Run `make verify-build` once at the end, because only it
  compiles the app, `OpenSkyCLI`, and the Xcode test bundles.
- `make verify-build` compiles the app, `OpenSkyCLI`, and the unit bundles without running
  a test; `make realdata-build` compiles `OpenSkyRealDataTests`. Together they are the
  cheapest way to catch a type change that breaks a target you did not test.
- `make health` fails on unused code (Periphery). Run it when a change adds, moves, or
  stops using declarations or imports. It builds uncached into its own tree, so its first
  run in a worktree is a full build.
- `make coverage-floor` after `make test-unit` fails when a parser module's coverage drops
  under the floor. Run it when a parser change deletes tests or adds untested branches.
- After a failure, `make test-report` names the failing tests and messages, and shows
  time per tag. Do not hand-parse `.xcresult` JSON.
- Every plan sets a time allowance. A test that fails on it is a hang to fix, not a
  limit to raise: a raised limit hides the next hang too.

## Long runs

These commands build, so the background-shell and one-`xcodebuild` rules in the root
`AGENTS.md` apply to them: `make test-unit` after an edit, `make verify-build`,
`make cli`, `make test-real`, `make health`, `make install`, and `git push`.

- Start the command itself in the background, not with `> file` redirection, and wait for
  the completion notification. Do not `cat` the task output, `sleep`, or loop on a log
  before it arrives. Each check is one more turn, and each turn re-reads the whole context.
- The output already lists each error once, with repository paths. Read it from the
  notification. Open the transcript only when the output says errors were not shown.
- The build removes stale module copies itself and retries while it finds new ones
  (`docs/tools/build-system.md`). Do not delete `.swiftmodule` folders by hand.

## UI tests

`make test-ui` is the slowest run here. Each UI test launches and drives the app for about
15 to 25 s, so the whole plan takes many minutes after the build. It also takes over the
screen while the user may be working.

- Run it only when the change can break what a UI test checks: a new or changed UI test, or
  a changed sidebar control or accessibility id that a UI test uses. Then run only those
  tests with `T='Suite/test()'`.
- Do not run it as a routine check for engine, parser, rendering, tooling, or docs changes.
  The unit tests and `make verify-build` cover those. Write `test-ui not run: no UI test
  path changed` in the `Tests:` section.
- Milestone acceptance is the one place where the whole plan runs.

## Real-data runs

These guard the machine and are not optional:

- Real-data tests go through `make test-real` or `make test-perf` only. Both run under the
  memory watchdog; a raw `xcodebuild` against the install once ran to 30 GB and locked the
  machine.
- Iterate with `make test-real T=...` on one test. Rerun it only after a change that could
  alter the result.
- A perf gate carries the `.perf` tag; `make test-perf` runs every one, built optimized.
- Captures and probe output go under `logs/` (root `AGENTS.md`, Legal & IP boundary).

## Flaky tests

A test that fails, then passes on the same code, is flaky. Do not rerun it until it passes,
and never add a retry: both hide a real bug. `make test-unit T='Suite/test()' N=100` shows it
fails sometimes. Then follow the rule in `Tests/AGENTS.md`: disable it with
`.disabled("flaky: #NNN")` and open a `bug` issue with the run directory.

## Report it

The commit body's `Tests:` section lists the exact commands run and their result, and says
what was deliberately not run and why (for example, `test-real not run: no real-data
path changed`). If something could not be verified, say so plainly rather than implying it
was.
