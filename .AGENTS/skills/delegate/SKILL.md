---
name: delegate
description: Orchestrate a milestone across sub-agents without each one re-deriving repo
  context - hand down the Explore brief, trust docs/index.md, verify worktree base branch,
  restate AGENTS.md criticals. Use when splitting a task across parallel/sequential agents.
---

# Delegating milestone work to sub-agents

Workflow for the orchestrator that fans a milestone out to implementer sub-agents.
Companion to root `AGENTS.md`. Problem this kills: each sub-agent independently
re-reading the same ~15 core files + re-deriving the same map (Refs #107 — three
subs once re-derived the identical 30 GB leak root cause). The orchestrator holds
the context; agents get it handed down, not rebuilt.

Core rules (this file wins on conflict with a default habit):

## Map once, hand it down

1. Run ONE Explore/Plan pass up front -> architecture brief: exact file paths +
   key type signatures the implementers touch. Orchestrator keeps it.
2. Paste that brief verbatim into EACH implementer's task prompt. Do not send a
   bare "implement X" and let the agent re-discover the layout.
3. Findings are shared, not re-derived. A root cause, a gotcha, a probe result
   found by agent A goes into B/C's prompt (or a scratch note) — never "each
   agent figures it out again".
4. Sub-agents trust `docs/index.md`'s path table + the relevant `docs/` page over
   globbing. Point them at the doc; the map is the doc's job, not a fresh grep.

## Split stages by dependency

- Independent stages -> parallel background agents in one message. Read-only /
  probe stages need no worktree.
- Repo-committing stages -> one at a time (serialize) to avoid index/lock races.
- Dependent stages -> sequential, after their input lands. Feed the upstream
  result into the downstream prompt.
- Match model to difficulty: sonnet mechanical, opus solid impl, fable trickiest
  (models explicitly allowed here).

## Worktree base-branch check at handoff

A worktree sub-agent that branches from stale `main` silently loses the feature
work. At handoff verify its base is the CURRENT feature branch, not `main`:
`git -C <worktree> rev-parse --abbrev-ref HEAD` + `git merge-base --is-ancestor
<feature-tip> HEAD`. Wrong base -> rebase before it commits, not after.

## Restate AGENTS.md criticals in every prompt

Sub-agents do not inherit this contract — spell it out each time:

- No AI commit trailers (`Co-authored-by:`, `Generated-by:`, ... — see `commit`).
- Conventional Commit body sections; `make check` + `make test` green per commit.
- Synthetic in-code fixtures only; never commit game data (`.bsa`/`.nif`/... ).
- Probes never land in commits; cite an open spec for any byte layout.

## Orchestrator keeps the narrative

Agents return raw findings; the orchestrator restates results in its own text
(sub-agent reports are not user-visible). Record the milestone's sidebar
verification path + same-commit `docs/` updates centrally — do not assume each
agent logged its own slice.
