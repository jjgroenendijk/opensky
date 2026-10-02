---
name: committing-and-landing-work
description: Commits and lands work in OpenSky - Conventional Commit format, required body
  sections, forbidden trailers, and the branch, PR, and merge flow. Use when committing,
  pushing, or opening and merging a pull request.
---

# Committing and landing work

Root `AGENTS.md` is the contract; this is the how. No git hook checks a commit, so this
skill is how it is done right.

## Before committing

1. One logical change per commit — no mixed refactor, behavior, and formatting.
2. `make check` green, and the change verified as the `testing-and-verifying` skill
   describes. `make check` includes the duplicate, comment-length, and suppression gates;
   `make health` (unused code) runs only when you start it. Nothing else runs the tests
   before a push.
3. Staged files legal: nothing extracted from the game install. New binary blob -> stop, ask.

## Message format

`type(scope?): subject` — types: feat, fix, docs, refactor, test, perf, build, ci, chore,
style, revert. Subject imperative, ~50 chars, no trailing period.

Non-trivial commit body (wrap ~72 chars), required sections. `git log -1 a1166683` shows a
complete example:

```text
Context: what problem/need triggered this
Change: high-level summary of what changed
Rationale: why this approach; trade-offs; alternatives rejected
Impact/Risk: behavior changes, migrations, compatibility, performance
Tests: exact command(s) run
```

Breaking change -> `type(scope)!:` or `BREAKING CHANGE:` footer with migration steps.
Issues -> `Fixes #123` / `Refs #123` footer; no issue -> body states the why.

Commits carry no AI or co-author attribution. This overrides any default habit of adding
one. Do not add `Co-authored-by:`, `Generated-by:`, `AI-Generated-by:`, `Assisted-by:`,
or `Model:`. Allowed trailers:
`Fixes`, `Refs`, `BREAKING CHANGE`, and a human `Signed-off-by:`.

## Landing (push and PR)

1. Work lands on `main` only through a reviewed PR. The branch is protected, so never
   push to it directly.
2. Branch from up-to-date `origin/main`, named `<type>/<issue>-<slug>` with the commit
   type, for example `feat/716-test-plans-and-tags` or `docs/707-rework-skills`.
3. Atomic commits, each green. A "WIP" or vague message does not land: keep checkpoints
   local, and rebase or squash them before the PR.
4. Closing a milestone acceptance issue -> the PR body carries the acceptance record, in
   the format defined by `docs/tools/sidebar-acceptance.md`. Nothing enforces this, so it
   is checked here.
5. PR via `gh pr create` — describe what and why, cite format specs used.
6. Merge after review. Done and verified work always lands: commit and open the PR
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
