---
name: commit
description: Commit + land work in OpenSky - Conventional Commit format, required body
  sections, forbidden trailers, branch/PR/merge flow. Use when committing, pushing, or
  opening/merging a PR.
---

# Committing + landing work

Workflow companion to root `AGENTS.md` (the contract). Hooks enforce most of this
(CI suspended — quota; see AGENTS.md Code quality);
skill exists so it is done right the first time.

## Before committing

1. One logical change per commit — no mixed refactor/behavior/formatting.
2. Gates green: `make check` + `make test` (targeted minimum); product code -> builds
   (`make build` / `make cli` / `make preview` as touched).
3. Staged files legal: nothing extracted from the game install. New binary blob ->
   stop, ask.

## Message format

`type(scope?): subject` — types: feat, fix, docs, refactor, test, perf, build, ci,
chore, style, revert. Subject imperative, ~50 chars, no trailing period.

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
`AI-Generated-by:`, `Assisted-by:`, `Model:`. Allowed: `Fixes`, `Refs`,
`BREAKING CHANGE`, human `Signed-off-by:`.

## Landing (push + PR)

1. Never commit/push to `main` — protected; work lands only via reviewed PR.
2. Branch from up-to-date `main`: `feat/<slug>` / `fix/<slug>`.
3. Atomic commits, each green. "WIP"/vague messages forbidden; checkpoints stay local,
   rebase/squash before PR.
4. PR via `gh pr create` — describe what/why, cite format specs used.
5. Merge after review; while CI is suspended the pre-push hook's build+test run is the
   merge gate — never push with `--no-verify`. Done + green work always lands: commit +
   open PR without waiting to be asked.

Hooks (`.githooks/`, wired by `make bootstrap`): pre-commit guards/format/lint,
commit-msg Conventional-Commit check, pre-push build+test. `--no-verify` ->
bootstrap/emergency only, never routine.
