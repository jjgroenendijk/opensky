---
name: starting-roadmap-work
description: Picks up and finishes OpenSky roadmap work on GitHub - area milestones and goal
  labels, choosing the next issue, writing an issue body, one branch and one PR per issue,
  labels, assigning an issue, the draft PR flow, and finishing a goal. Use when choosing
  what to work on, filing or editing an issue, picking its milestone, starting an issue, or
  finishing a goal.
---

# Starting roadmap work

Open work lives in GitHub issues and milestones. There is no roadmap file in the repo, so a
fresh session starts from `gh`, not from a doc.

## How the roadmap maps to GitHub

- A milestone is an area of the code, such as `Rendering + audio` or `Gameplay systems`.
  An area never closes. `gh api repos/{owner}/{repo}/milestones --jq '.[].title'` lists
  them. The milestone description says what belongs in the area, what does not, its spec
  references, and legal notes. It names no dates, issue or PR numbers, outcomes, or status,
  because those go stale and the issue list and merged PRs already show them.
- Every issue has one milestone: the area where most of its change lands. An issue that
  spans areas goes to the area of its root cause.
- A goal is a deliverable that spans areas, such as the Helgen opening. It is a
  `goal:<name>` label. One issue of the goal carries the `acceptance-gate` label and holds
  the goal's acceptance gate and its list of issues.
- Issue titles carry no item numbers. A title states the problem or the result.
- Labels: `roadmap`, `acceptance-gate`, `goal:<name>`, `bug`, `format-parser`, `app-ui`.
- The `OpenSky roadmap` project board
  (<https://github.com/users/jjgroenendijk/projects/7>) is a view across areas. It is not
  the source of truth. Live branch and PR state comes from `gh pr list` and `git log`.

## Choosing the next item

1. Take the goal the user names. With none named, list the goals:
   `gh label list --search goal:`. Then list one goal's issues:
   `gh issue list --label goal:opening`.
2. Read the goal's acceptance issue. Take the issue it lists first that is still open.
   Bugs that block the goal come before new features. Skip an issue that has an assignee
   or an open PR (`gh pr list --state open`): another session is working on it.
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
- A gap found in the area the task touches, such as a missing shader term or record field,
  goes in this PR, after a check of that area for more gaps (root `AGENTS.md`).
- A problem found in an area the task does not touch becomes a new issue
  (`gh issue create`, with the `bug` label for a bug). Do not fix it in this PR unless it
  blocks the task, so the PR stays about one issue and the problem is not lost.
- A performance idea becomes a new issue too, one issue per idea. The title states the
  win; the body states why it can be faster. No measurement is needed to file it. Do not
  make the change in this PR.

## Finishing a goal

- Every merged PR keeps its area milestone, so `gh pr list --state merged --milestone
  "Gameplay systems"` shows how an area was built.
- A goal is done when every issue with its label is closed. The PR that closes the goal's
  acceptance issue carries the acceptance record in the format of
  `docs/tools/sidebar-acceptance.md`, and runs the checks that the `testing-and-verifying`
  skill lists for acceptance.
- Record the outcome in that PR, not in a milestone description or a label. Project history
  lives in git, merged PRs, and closed issues, never in `docs/`.
