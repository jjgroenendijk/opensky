---
name: delegating-to-subagents
description: Orchestrates a milestone across sub-agents so no agent re-derives repo context -
  hands down the Explore brief, points sub-agents at docs/index.md, verifies the worktree base
  branch, and restates the AGENTS.md criticals. Use when splitting a task across parallel or
  sequential agents.
---

# Delegating milestone work to sub-agents

For the orchestrator that fans a milestone out to implementer sub-agents. The problem this
kills: every sub-agent independently re-reading the same core files and re-deriving the same
map (Refs #107 — three sub-agents once re-derived one identical memory-leak root cause). The
orchestrator holds the context; sub-agents get it handed down, not rebuilt.

These rules win over a default habit when the two conflict.

## Map once, hand it down

1. Run ONE Explore or Plan pass up front, producing an architecture brief: exact file paths
   plus the key type signatures the implementers touch. The orchestrator keeps it.
2. Paste that brief verbatim into EACH sub-agent's task prompt. Do not send a bare
   "implement X" and let the sub-agent rediscover the layout.
3. Findings are shared, not re-derived. A root cause, a gotcha, or a probe result found by
   one sub-agent goes into the next one's prompt (or a scratch note) — never "each sub-agent
   figures it out again".
4. Sub-agents trust the path table in `docs/index.md` and the relevant `docs/` page over
   globbing. Point them at the doc; mapping the repo is the doc's job, not a fresh grep.

## Split stages by dependency

- Independent stages -> parallel background sub-agents in one message. Read-only and probe
  stages need no worktree.
- Repo-committing stages -> one at a time, to avoid index and lock races.
- Dependent stages -> sequential, after their input lands. Feed the upstream result into the
  downstream prompt.
- Match model tier to difficulty: the cheapest tier for mechanical edits, the default
  implementation tier for ordinary feature work, and the strongest tier only for the hardest
  slice. Naming a model explicitly is allowed here, unlike elsewhere.

## Worktree base-branch check at handoff

A worktree sub-agent that branches from a stale `main` silently loses the feature work. At
handoff, verify its base is the CURRENT feature branch, not `main`:
`git -C <worktree> rev-parse --abbrev-ref HEAD` plus
`git merge-base --is-ancestor <feature-tip> HEAD`. Wrong base -> rebase before it commits,
not after.

## Restate the AGENTS.md criticals in every prompt

Sub-agents do not inherit this contract, so spell it out each time:

- No AI commit trailers, and the Conventional Commit body sections (full rules in the
  `committing-and-landing-work` skill).
- `make check` plus `make test` green per commit.
- Synthetic fixtures built in code only; never commit game data (`.bsa`, `.nif`, ...).
- Probes never land in commits; cite an open spec for any byte layout.

## The orchestrator keeps the narrative

Sub-agents return raw findings; the orchestrator restates results in its own text, because
sub-agent reports are not user-visible. Record the milestone's sidebar verification path and
the same-commit `docs/` updates centrally — do not assume each sub-agent logged its own slice.
