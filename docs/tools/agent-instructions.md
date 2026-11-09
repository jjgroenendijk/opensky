---
type: Tool
title: Agent instructions and their gates
description: Which rules in the agent files and skills a machine checks, the gate that checks
  each one, the rules that stay as text with their reason, and the line counts.
tags: [tool, agents, skills, lint]
---

# Agent instructions and their gates

The agent files (`AGENTS.md` at the root and in some folders) and the skills in
`.agents/skills/` hold the rules an agent follows. A rule that a machine checks is written
there once, in one line that names its gate. A gate is a check that fails the run: a script
in `tools/lint/` or `tools/format/`, a SwiftLint rule, or the compiler. `make check` and CI run
every gate. The text keeps only what no gate can hold, and the reason for it.

A rule written twice is read once, and a long file is skimmed. The rule that matters most,
the legal boundary, is then read less.

## Rules a gate holds

| Rule | Gate |
| --- | --- |
| No game content, no capture, and no wiki page in git | `tools/lint/no-game-content.sh` |
| App-only code stays in `OpenSky/`, CLI-only code in `OpenSkyCLI/` | `tools/lint/cli-boundary.sh` |
| A feature uses another only through its `Interface` module; no import of a higher layer | `tools/lint/module-graph.sh` |
| Swift 6 mode, the same Swift locally and in CI | `tools/lint/swift-baseline.sh` |
| `any X`, `internal` imports, `unsafe` marks | `tools/lint/language-rules.sh` and the compiler |
| No `try?` outside `removeItem` and `close`; typed errors | `tools/lint/error-handling.sh` |
| A condition context carries its function registry; no function takes both apart | `tools/lint/condition-context.sh` |
| No system random source, clock, mutable static, or singleton in game rules | `tools/lint/deterministic-rules.sh` |
| No `@unchecked Sendable`, `Task.detached`, or new `DispatchQueue` | SwiftLint `unchecked_sendable`, `detached_task`, and the queue rules |
| No `GameViewController+X.swift` file; no late setter or connection step | SwiftLint `game_view_controller_extension`, `late_setter_method`, `late_attached_world`, `connection_step_type` |
| Ports and adapters | `tools/lint/app-architecture.sh`, `tools/lint/adapter-rules.sh` |
| Records read through the whole load order | `tools/lint/load-order-only.sh` |
| A file stays under 800 lines | `tools/lint/file-length.sh` and the pre-commit hook |
| A comment block stays under 7 lines; no suppression; no duplicated code | `tools/lint/comment-length.sh`, `no-suppressions.sh`, `duplicates.sh` |
| A module stays under its size limit | `tools/lint/module-size.sh` |
| A real-data suite lives in `OpenSkyRealDataTests` | `tools/lint/realdata-plan.sh` |
| `UnitTests` lists every unit bundle; no UI bundle beside a hosted one | `tools/lint/test-plans.sh` |
| Test tags, `.unlessPlanSkips`, and a `.disabled` trait that names an issue | `tools/lint/test-tags.sh` |
| Random test order, no `.serialized` | `tools/lint/test-order.sh` |
| A doc or script names only make targets that exist | `tools/lint/make-targets.sh` |
| Docs links resolve and pages stay short | `tools/lint/docs-links.sh`, `tools/lint/docs-length.sh` |
| Each `AGENTS.md` has its `CLAUDE.md` link; skills keep their format | `tools/lint/agent-files.sh` |
| Formatting of Swift, Metal, C++, Python, and Markdown | `make format-check` (`tools/format/`) |

## Rules only the text holds

No gate can check these, so the text states each one with its reason:

- The legal boundary: no copied Bethesda or SKSE code. Code from memory looks like any other
  code, so no script can find it.
- Where things live, and which document or skill to read before a kind of work.
- How to work: one issue per branch and PR, one build after a batch of edits, the smallest
  test plan that covers the change, and an issue for each bug, gap, or performance idea found.
- Build in a linked worktree, one per issue (`testing-and-verifying` skill). Two builds into
  one build tree collide, and no lock stops them.
- A new check with findings across the tree lands in slices: a report with its count, then
  the fixes per module, then the gate once the count on `main` is zero (`starting-roadmap-work`
  and `committing-and-landing-work` skills). Measured 2026-11-08: one PR that added a gate and
  fixed the whole tree was open 13.5 hours, with 8 CI runs, 7 of them failed.
- The writing style, and what a comment may hold.

## Line counts

Measured 2026-11-09, before and after the gated rules became one line each.

| File | Before | After |
| --- | --- | --- |
| `AGENTS.md` | 271 | 148 |
| `src/Sources/AGENTS.md` | 73 | 68 |
| `src/Tests/AGENTS.md` | 130 | 118 |
| `src/Tests/HostedTestSupport/AGENTS.md` | 45 | 29 |
| `src/Tests/OpenSkyRealDataTests/AGENTS.md` | 55 | 42 |
| `src/Tests/OpenSkyTests/AGENTS.md` | 56 | 28 |
| `reference/AGENTS.md` | 23 | 22 |
| Eleven skills | 1,100 | 1,109 |

The skills grew by the worktree and slice rules. Their gated rules already named the gate.
