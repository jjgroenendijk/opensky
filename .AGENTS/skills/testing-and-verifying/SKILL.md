---
name: testing-and-verifying
description: Decides what to test and verify for a change in OpenSky and how to run it
  cheaply - picking suites from the diff, the fast test loop, compile checks across targets,
  real-data and render verification, and what to report. Use before running any test,
  build check, or verification, and before pushing.
---

# Testing and verifying

No hook runs the tests or builds. What gets tested and scanned before a push is your call,
and the commit's `Tests:` section records it. Aim for
evidence proportional to risk: enough that you would bet the change works, no more.
The mechanics behind every command below are in `docs/testing.md`.

## Pick what to run from the diff

Start from `git diff --stat main...` and ask what could break, including code the diff did
not touch but that calls into it. Reasonable defaults, not rules:

| Change | Evidence |
| --- | --- |
| Docs, skills, Markdown only | `make check` |
| Hook, Makefile, or `tools/` script | `make check`, then run the changed target or script once |
| Parser or math routine | New or updated synthetic-fixture tests, `make test-fast T='Suite'` for the suites that cover it |
| Engine logic in one subsystem | `make test-fast T='Suite'` for its suites, then `make test-fast` (whole unit plan) once before pushing |
| Shared types, `ShaderTypes.h`, project or `Config/` files, file moves between `App/` and `Engine/` | `make verify-build`, then `make test-fast` |
| Rendering or shaders | Unit tests plus an offscreen render the user can look at (`probing-real-game-data` skill); a green build does not prove a triangle appeared |
| Behavior that only shows on the real install | `make realtest T='Class/method()'`, one run per affected test |
| App UI | `building-app-ui` skill; `make test-ui` when a smoke-test path changed |
| Milestone acceptance | `make realtest-all`, `make test-sanitize`, `make test-ui`, and the record in `docs/tools/sidebar-acceptance.md` |

Find the suites for a file with `grep -rl 'TypeName' openskyTests openskyRealDataTests`.
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
- `make verify-build` compiles the app, `openskycli`, and both unit bundles without running
  a test. It is the only routine command that compiles `openskyRealDataTests`, and the
  cheapest way to catch a type change that breaks a target you did not test.
- `make dead-code` scans for new unused code. Run it when a change adds, removes, or stops
  using declarations. It builds uncached into its own tree, so its first run in a worktree
  is a full build.
- After a failure, `make test-report` names the failing tests and messages. Do not
  hand-parse `.xcresult` JSON.

## Long runs

Anything that builds (`make test-fast` after an edit, `make test`, `make verify-build`,
`make cli`, `make realtest`, `make dead-code`, `make install`) can pass the
two-minute tool timeout. Start it with `run_in_background` and wait for the completion
notification rather than polling a log.

Only one `xcodebuild` per derived-data tree at a time; two deadlock. That includes
`git push`, whose hook builds. Start nothing until the running build reports done.

## Real-data runs

These guard the machine and are not optional:

- Real-data tests go through `make realtest` or `make realtest-all` only. Both run under the
  memory watchdog; a raw `xcodebuild` against the install once ran to 30 GB and locked the
  machine.
- Iterate with `make realtest T=...` on one test. Rerun it only after a change that could
  alter the result; a flaky result needs its cause found, not a second run.
- Captures and probe output go under `logs/` and never into a commit (`AGENTS.md`, Legal).

## Report it

The commit body's `Tests:` section lists the exact commands run and their result, and says
what was deliberately not run and why (for example, `realtest-all not run: no real-data
path changed`). If something could not be verified, say so plainly rather than implying it
was.
