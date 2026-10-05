---
name: starting-roadmap-work
description: Picks up and finishes OpenSky roadmap work on GitHub - how milestones map to
  Mn, choosing the next issue, writing an issue body, one branch and one PR per issue,
  labels, assigning an issue, the draft PR flow, and closing a milestone. Use when
  choosing what to work on, filing or editing an issue, starting an issue, or finishing a
  milestone.
---

# Starting roadmap work

Open work lives in GitHub issues and milestones. There is no roadmap file in the repo, so a
fresh session starts from `gh`, not from a doc.

## How the roadmap maps to GitHub

- GitHub milestone `#n` is OpenSky milestone `Mn`. The milestone description says what
  belongs in the milestone: its scope, spec references, and legal notes. It names no
  dates, issue or PR numbers, item numbers, outcomes, or status, because those go stale
  and the issue list and merged PRs already show them.
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
   Skip an item that has an assignee or an open PR (`gh pr list --state open`): another
   session is working on it.
3. Read the issue body. Its acceptance gate is what "done" means.

## Writing an issue body

An issue states intent: what must be true afterwards, why, and how to know it is done. Code
changes faster than issues are worked, and a refactor makes a named file or line wrong. A
wrong location misleads the agent that picks the issue up, so that agent finds the current
code itself.

- Keep: the goal and its reason; an acceptance gate written as observable behavior; spec
  and format references (`docs/formats/` pages, UESP, xEdit); game behavior; legal notes;
  links to other issues and milestones; measurements, with their `.logs/` run directory.
- Leave out: file paths, line numbers, type or function names used to say where a change
  goes, pasted code of the current implementation, and step-by-step plans tied to the
  current code structure.
- A record, format, or feature named as the subject is fine, such as "the `.xwm` framing
  parser" or "`XLOC` lock data".

## Working an item

1. Assign the issue to yourself before any other step:
   `gh issue edit NNN --add-assignee @me`. The assignee shows other sessions that someone
   works on it.
2. Branch from `origin/main`, make the first atomic commit, push it, and open a draft PR:
   `gh pr create --draft`. The PR body closes the issue with `Closes #NNN`. CI runs the
   whole unit plan on every push, so the draft collects test results while the work goes on.
3. Push each further atomic commit to the draft PR as it is done.
4. When the acceptance gate is met and verified, mark the PR ready:
   `gh pr ready <pr>`.

- One branch and one PR per issue.
- Load the skill for the kind of work: `implementing-format-parsers`, `building-app-ui`,
  `testing-and-verifying`, and `committing-and-landing-work` to land it.
- Scope changes are issue edits, not doc edits.
- A problem found during the work that the current change did not cause becomes a new
  issue (`gh issue create`, with the `bug` label for a bug). Do not fix it in this PR
  unless it blocks the task, so the PR stays about one issue and the problem is not lost.
- A performance idea becomes a new issue too, one issue per idea. The title states the
  win; the body states why it can be faster. No measurement is needed to file it. Do not
  make the change in this PR.

## Finishing a milestone

- Every merged PR is assigned to the milestone it landed under. A closed milestone keeps
  that record: `gh pr list --state merged --milestone "M4 - walkable world"` shows how it
  was built.
- The closing PR carries the acceptance record in the format of
  `docs/tools/sidebar-acceptance.md`.
- Record the outcome in the closing PR, not in the milestone description, then close the
  milestone. Project history lives in git, merged PRs, and closed issues, never in `docs/`.
