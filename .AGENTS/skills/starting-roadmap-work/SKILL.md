---
name: starting-roadmap-work
description: Picks up and finishes OpenSky roadmap work on GitHub - how milestones map to
  Mn, choosing the next issue, one branch and one PR per issue, labels, and closing a
  milestone. Use when choosing what to work on, starting an issue, or finishing a milestone.
---

# Starting roadmap work

Open work lives in GitHub issues and milestones. There is no roadmap file in the repo, so a
fresh session starts from `gh`, not from a doc.

## How the roadmap maps to GitHub

- GitHub milestone `#n` is OpenSky milestone `Mn`. The milestone description holds the
  goal, spec references, and legal notes.
- Each issue is one numbered roadmap item, such as `9.1.2 .xwm framing parser`, and carries
  its own acceptance gate.
- Labels: `roadmap`, `acceptance-gate`, `format-parser`, `app-ui`.
- The `OpenSky roadmap` project board
  (<https://github.com/users/jjgroenendijk/projects/7>) is a view across milestones. It is
  not the source of truth. Live branch and PR state comes from `gh pr list` and `git log`.

## Choosing the next item

1. List the milestone: `gh issue list --milestone "M9 - audio"`.
2. Take the lowest open item by its roadmap number (`9.1.2` before `9.1.3`), not by issue
   number. Issues inserted later get higher numbers than the items around them.
   Skip an item that already has an open PR (`gh pr list --state open`): another session
   is working on it.
3. Read the issue body. Its acceptance gate is what "done" means.

## Working an item

- One branch and one PR per issue. The PR body closes it with `Closes #NNN`.
- Load the skill for the kind of work: `implementing-format-parsers`, `building-app-ui`,
  `testing-and-verifying`, and `committing-and-landing-work` to land it.
- Scope changes are issue edits, not doc edits.

## Finishing a milestone

- Every merged PR is assigned to the milestone it landed under. A closed milestone keeps
  that record: `gh pr list --state merged --milestone "M4 - walkable world"` shows how it
  was built.
- The closing PR carries the acceptance record in the format of
  `docs/tools/sidebar-acceptance.md`.
- Record the outcome in the milestone description or the closing PR, then close the
  milestone. Project history lives in git, merged PRs, and closed issues, never in `docs/`.
