---
type: Task List
title: Outstanding setup work
description: Remaining tasks to finish OpenSky dev-tooling bootstrap and first push.
tags: [meta, tooling, bootstrap]
timestamp: 2026-07-09T00:00:00Z
---

# TODO — bootstrap finish

State as of 2026-07-09. Dev tooling mostly written but not yet committed/pushed.
Repo flattened to `/Volumes/data/opensky` (was `opensky/opensky`).

## Done

* AGENTS.md rewritten: legal/IP, stack, layout, OKF wiki, code quality, commits,
  git workflow, tooling, writing style. Unnumbered headings, no AI-attribution trailers.
* tools/ layout: `tools/format/.swiftformat`, `tools/lint/.swiftlint.yml`,
  `tools/markdown/.markdownlint-cli2.yaml`, `tools/bootstrap.sh`.
* .githooks/ wrapper + numbered-script structure. `core.hooksPath=.githooks/hooks` wired.
* Makefile automation hub, `.github/workflows/ci.yml`, `.gitignore`, `logs/`, docs seed.

## Blockers to green local gate

* Fix `make sh-lint`: shellcheck SC2034 -> `FORBIDDEN_EXT_RE` in `.githooks/lib.sh`
  flagged unused (used cross-file via sourcing). Add `# shellcheck disable=SC2034` or export.
* Fix `make md-lint`: markdownlint lints `._*` AppleDouble junk (this volume writes them).
  Add ignore `**/._*` to `tools/markdown/.markdownlint-cli2.yaml`. Real .md files pass.
* `make format-check` (swift): Xcode template unformatted -> run `make format`.
* `make swift-lint`: template fails strict lint. Violations: `force_unwrapping`,
  `force_try`, `force_cast` in Renderer.swift; `function_body_length`/`type_body_length`;
  lowercase test type names (`openskyTests`); `sorted_imports`; `unused_optional_binding`.
  Decide -> clean up template to pass, or scope-exclude until engine replaces it.
  Note: force-* are hard errors on purpose (external-data safety). Real fix = rewrite,
  not suppress.

## Bootstrap junk cleanup

* Initial Commit tracked 14 `._*` AppleDouble files. Already `git rm --cached`ed (staged
  as deletions). Confirm none re-enter; `.gitignore` has `._*`.

## Verify hooks end-to-end

* On a branch: make a dummy commit -> confirm pre-commit (format+lint+guards) and
  commit-msg (conventional) fire. Confirm pre-commit blocks on `main`.
* Confirm pre-push blocks push to `main` and runs build/test (OPENSKY_SKIP_BUILD=1 to skip).

## GitHub (requested: create private repo + push)

* `gh repo create opensky --private` (owner jjgroenendijk). Add remote.
* Establish `main` on remote (bootstrap push may need `--no-verify` since our own pre-push
  blocks main; enable protection right after).
* Enable branch protection / ruleset on `main`: require PR, require CI status checks
  (`quality`, `build-test`), no direct pushes.
* Land tooling via the real flow: branch `chore/dev-tooling` -> atomic commit(s) -> PR.
  gh auth already present (user jjgroenendijk, ssh).

## Open questions

* Metal shader (`.metal`) formatter/linter? No standard tool. AGENTS.md says every language
  needs both — decide tool or document exception.
* Commit-msg hook validates subject only. Body-section requirement (Context/Change/
  Rationale/Impact/Tests) enforced by review/CI, not the hook. Add a check?
* CI runner Xcode version: `macos-latest` may lag Xcode 26 / Metal 4. Pin when it matters.
