---
name: testing-and-verifying
description: Decides what to test and verify for a change in OpenSky and how to run it
  cheaply - picking suites from the diff, the fast test loop, compile checks across targets,
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
| Parser or math routine | New or updated synthetic-fixture tests, `make test-fast T='Suite'` for the suites that cover it |
| Engine logic in one subsystem | `make test-fast T='Suite'` for its suites, then `make test-fast` (whole unit plan) once before pushing |
| Shared types, `ShaderTypes.h`, project or `Config/` files, file moves between `OpenSky/` and a package module | `make verify-build`, then `make test-fast` |
| Rendering or shaders | Unit tests plus an offscreen render the user can look at (`probing-real-game-data` skill); a green build does not prove a triangle appeared |
| Behavior that only shows on the real install | `make realtest T='Class/method()'`, one run per affected test |
| App UI | `building-app-ui` skill; `make test-ui` when a smoke-test path changed |
| A performance claim or a per-frame loop to speed up | `make profile` before and after, Release build (`docs/testing.md`, Profiling); one issue per finding |
| Milestone acceptance | `make realtest-all`, `make test-sanitize`, `make test-ui`, and the acceptance record (format in `docs/tools/sidebar-acceptance.md`) in the closing PR |

Find the suites for a file with `grep -rl 'TypeName' Tests`.
Suite names follow the type under test (`BSAArchive` is covered by `BSAArchiveTests`).

A behavior change without a test that would have failed before it is unverified: write the
test first, watch it fail, then fix.

## Run it cheaply

- `make test-fast` is the default for every unit run, filtered or whole plan. It builds only
  when a source is newer than the cached products; `B=1` forces a rebuild if in doubt.
  `make test` (the full build-system path) is only for a clean re-check after something
  odd, such as a result that does not match the code.
- `make test-fast T='Suite'` runs a whole suite; `T='Suite/method()'` runs one test. A
  selector that matches nothing fails loudly with near-matches, so a typo cannot pass.
- Batch several edits into one run instead of rerunning after each edit.
- While fixing compile errors in package modules, loop on `make compile` (or
  `make compile M='OpenSkyWorld'`). It runs `swift build` on the changed modules and their
  dependents, without Xcode. Run `make verify-build` once at the end, because only it
  compiles the app, `OpenSkyCLI`, and the Xcode test bundles.
- `make verify-build` compiles the app, `OpenSkyCLI`, and both unit bundles without running
  a test. It is the only routine command that compiles `OpenSkyRealDataTests`, and the
  cheapest way to catch a type change that breaks a target you did not test.
- After a failure, `make test-report` names the failing tests and messages. Do not
  hand-parse `.xcresult` JSON.

## Long runs

These commands build, so the background-shell and one-`xcodebuild` rules in the root
`AGENTS.md` apply to them: `make test-fast` after an edit, `make test`, `make verify-build`,
`make cli`, `make realtest`, `make install`, and `git push`.

- Start the command itself in the background, not with `> file` redirection, and wait for
  the completion notification. Do not `cat` the task output, `sleep`, or loop on a log
  before it arrives. Each check is one more turn, and each turn re-reads the whole context.
- The output already lists each error once, with repository paths. Read it from the
  notification. Open the transcript only when the output says errors were not shown.
- The build removes stale module copies itself and retries while it finds new ones
  (`docs/tools/build-system.md`). Do not delete `.swiftmodule` folders by hand.

## Real-data runs

These guard the machine and are not optional:

- Real-data tests go through `make realtest` or `make realtest-all` only. Both run under the
  memory watchdog; a raw `xcodebuild` against the install once ran to 30 GB and locked the
  machine.
- Iterate with `make realtest T=...` on one test. Rerun it only after a change that could
  alter the result; a flaky result needs its cause found, not a second run.
- Captures and probe output go under `logs/` (root `AGENTS.md`, Legal & IP boundary).

## Report it

The commit body's `Tests:` section lists the exact commands run and their result, and says
what was deliberately not run and why (for example, `realtest-all not run: no real-data
path changed`). If something could not be verified, say so plainly rather than implying it
was.
