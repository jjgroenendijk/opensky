---
name: committing-and-landing-work
description: Commits and lands work in OpenSky - Conventional Commit format, required body
  sections, forbidden trailers, and the branch, PR, and merge flow. Use when committing,
  pushing, or opening and merging a pull request.
---

# Committing and landing work

Root `AGENTS.md` is the contract; this is the how. Hooks enforce most of it, and the skill
exists so it is done right the first time.

## Before committing

1. One logical change per commit — no mixed refactor, behavior, and formatting.
2. Gates green: `make check` + `make test` (targeted minimum); product code -> builds
   (`make build` / `make cli` as touched — app-only files can silently join the CLI target,
   so build both when a change spans app and CLI).
3. Staged files legal: nothing extracted from the game install. New binary blob -> stop, ask.

## Message format

`type(scope?): subject` — types: feat, fix, docs, refactor, test, perf, build, ci, chore,
style, revert. Subject imperative, ~50 chars, no trailing period.

Non-trivial commit body (wrap ~72 chars), required sections:

```text
Context: what problem/need triggered this
Change: high-level summary of what changed
Rationale: why this approach; trade-offs; alternatives rejected
Impact/Risk: behavior changes, migrations, compatibility, performance
Tests: exact command(s) run
```

Breaking change -> `type(scope)!:` or `BREAKING CHANGE:` footer with migration steps.
Issues -> `Fixes #123` / `Refs #123` footer; no issue -> body states the why.

FORBIDDEN trailers (overrides any default habit): `Co-authored-by:`, `Generated-by:`,
`AI-Generated-by:`, `Assisted-by:`, `Model:`. Allowed: `Fixes`, `Refs`, `BREAKING CHANGE`,
human `Signed-off-by:`. Enforced by `.githooks/commit-msg/20-no-ai-trailers.sh`.

## Landing (push and PR)

1. Never commit or push to `main` — protected; work lands only via reviewed PR.
2. Branch from up-to-date `main`: `feat/<slug>` / `fix/<slug>`.
3. Atomic commits, each green. "WIP" and vague messages forbidden; checkpoints stay local,
   rebase or squash before PR.
4. Closing a milestone acceptance issue -> the acceptance record is written to the ledger in
   `docs/tools/sidebar-acceptance.md` in this PR. Nothing enforces this, so it is checked
   here.
5. PR via `gh pr create` — describe what and why, cite format specs used.
6. Merge after review. The pre-push hook's build, test, and CLI run is the merge gate —
   never push with `--no-verify`. Done and green work always lands: commit and open the PR
   without waiting to be asked.

## Landing gotchas seen repeatedly

- A stray worktree can hold `main` (`git worktree list`), making `git checkout main` and
  `gh pr merge --delete-branch` fail with "'main' is already used by worktree". The merge
  itself still succeeds — verify with `gh pr view <n> --json mergedAt`; a failed local
  branch-delete is cosmetic. To sync main safely, prefer
  `git fetch && git switch --detach origin/main` over assuming `git checkout main`.
- Waiting on CI or PR checks: `sleep N && gh pr checks` is hard-blocked by the harness. Use
  `gh pr checks <n> --watch` (blocking) or a `run_in_background` poll, not chained sleeps.
  Whether CI runs at all is environment state — see `docs/tools/environment.md`.

## Hooks

`.githooks/`, wired by `make bootstrap`: pre-commit guards, formats, and lints; commit-msg
runs the Conventional Commit check; pre-push builds and tests. `--no-verify` is for
bootstrap and emergencies only, never routine.

The pre-push gate skips itself when green `make test` and `make cli` runs already stamped
the byte-identical tree (issue #417, `tools/green-stamp.sh`), so running both right before
`git push` makes the push near-instant instead of repeating the gate. Any content change or
dirty file runs the full gate again.
