---
type: Decision
title: Test order and coverage rules
description: Why tests run in random order, which code keeps a coverage floor, and how the diff-coverage check works.
---

# Test order and coverage rules

Machine checks keep the tests honest. Tests run in a new order on each run, the game rules
stay covered, and new code arrives with tests. Each rule below has a check, and each check
first runs on small synthetic violations, which must fail (a self-check).

| Rule | Check | Runs in |
| --- | --- | --- |
| Every test plan shuffles its tests | `tools/lint/test-order.sh` | `make check`, CI |
| No Swift Testing suite is `.serialized` | `tools/lint/test-order.sh` | `make check`, CI |
| Format, rule, and core floors | `make test PLAN=UnitTests COVERAGE=1` | CI, after the unit tests |
| Diff coverage | `make test COVERAGE=1` | CI on a pull request, after the unit tests |
| The coverage scripts catch a violation | `make check` | `make check`, CI |

## Random order

Tests that always run in the same order can depend on each other without anyone noticing:
one test leaves state behind, and the next one passes only because of it.

- XCTest runs its tests in the order of the source unless the test plan sets
  `randomExecutionOrdering`. Every target of every plan sets it.
- Swift Testing has no shuffle switch. It runs tests in parallel, so their order changes
  from run to run. The `.serialized` trait turns that off and runs a suite in source order,
  so no suite carries it. A suite that shares state with other tests reads only its own part
  of it instead, as `EngineLoggerTests` reads only the log lines of its own category.

## Coverage floors

The floors read the merged profile of the recent `make test COVERAGE=1` runs with `llvm-cov`
([Test runs](/tools/test-runs.md#code-coverage)). Each value is our own choice: no source
gives a number. `tools/coverage/floor.sh` and `tools/coverage/changed-lines.sh` hold the values.

| Floor | Value | Applies to | Why this value |
| --- | --- | --- | --- |
| `COVERAGE_FLOOR` | 80 % | each `OpenSkyFormats*` module | Parsers read untrusted files. The lowest module was 83 % when the floor was set |
| `RULE_COVERAGE_FLOOR` | 55 % | each feature, interface, and world-domain module, except a composition module such as `OpenSkySession` and its interface, which hold ports and wiring | The lowest of these modules on the CI runner, rounded down to a multiple of 5, as for the parsers: `OpenSkyWorld` at 57.9 %. Some of these modules hold Metal and file shells that only the GPU and real-data runs reach |
| `CORE_COVERAGE_FLOOR` | 75 % | each pure core file (`*Core.swift`) | A core is values in, values out, so nearly every line is reachable from a test. The rest are readout sentences of rare outcomes |
| `DIFF_COVERAGE_FLOOR` | 80 % | the package lines a pull request adds or changes | New code is the cheapest code to test: its author knows what it does |

A floor is the same for every module of its kind. One value per kind, not one per module,
leaves room for the GPU tests that skip on a CI runner without Metal 4, and it keeps a weak
module from setting its own low bar. A module under its floor gets tests; the floor does not
move down.

## Diff coverage

A floor on a whole module can fall slowly, one untested change at a time. `make
diff-coverage` reads the lines a branch adds or changes in package modules since `DIFF_BASE`
(by default the merge base with `origin/main`). On a pull request CI passes `HEAD^1`, the base
side of the merge commit it checks out.

1. At least `DIFF_COVERAGE_FLOOR` of the changed executable lines ran in a test.
2. Every function the branch adds ran in a test. A function counts as added when its first
   line is a changed line. A closure is not counted here, because a closure that never ran
   inside a tested function is an untaken branch, and rule 1 counts its lines. The init
   accessor the compiler adds to a property-wrapped stored property is not counted either. It
   runs only when an init assigns the property, so a property with a default value never
   calls it. Example: `@Flag var hidden = false`.

A line that git's moved-code detection (`git diff --color-moved`) marks as moved unchanged is
not a changed line, even when its indentation changed. Moving a type to another module does
not make its code new, as rename detection already does for a whole file. A moved line that
also changed, for example one that gained `public`, still counts. Example: moving
`struct Ward { func absorb() }` to an interface module counts nothing; making `absorb()`
public there counts its first line.

The app and the CLI targets are outside both rules: they are not package modules, and the UI
tests cover them. The modules declared with `composition()` and their interfaces, such as
`OpenSkyMagicAdapters` and `OpenSkySessionInterface`, are outside too, for the reason the
rule floor leaves them out: they hold ports and wiring, not game rules. A game rule found in
an adapter moves into its feature module, where both rules apply.
