---
name: writing-wiki-docs
description: Writes and updates the docs/ knowledge wiki - OKF v0.1 frontmatter, reserved
  files (index.md, log.md), link style, and the rule that open work stays in GitHub. Use
  whenever adding or materially changing anything under docs/.
---

# docs/ wiki — Open Knowledge Format

`docs/` follows Google Open Knowledge Format (OKF v0.1):
<https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md>. The wiki
holds reverse-engineered formats, subsystem design, and decisions — knowledge that must
survive across sessions. Doc updates land in the same commit as the change they document.

## File rules

- Bundle root `docs/`, a plain tree of `.md`. Group by domain: `formats/`, `engine/`,
  `rendering/`, `decisions/`, `tools/`.
- Every non-reserved `.md` starts with YAML frontmatter, at least a non-empty `type`.
  Recommended order: `title`, `description`, `resource`, `tags`, `timestamp` (ISO 8601, set
  to the date you are writing):

  ```markdown
  ---
  type: File Format
  title: BSA Archive
  description: On-disk layout of Skyrim SE .bsa archives and how OpenSky reads them.
  tags: [format, archive, io]
  timestamp: <today, ISO 8601>
  ---
  ```

- Concept ID = path minus `.md` (`docs/formats/bsa.md` -> `formats/bsa`).
- Reserved names, optional, at any level: `index.md` (directory listing, no frontmatter,
  `* [Title](/path.md) - description` lines) and `log.md` (change history, newest first,
  ISO-8601 date headings).
- Links are bundle-absolute from `docs/`: `[BSA](/formats/bsa.md)`. This form applies inside
  `docs/` only — a file outside `docs/`, such as a skill, uses a repo-relative path
  (`docs/formats/bsa.md`). Broken links are tolerated; relationship comes from prose.
- A reference page over 100 lines opens with a `## Contents` list of its own sections, so a
  partial read still shows the full scope.
- `log.md` merges with `merge=union` (root `.gitattributes`, issue #108): parallel PRs
  prepending entries merge clean, both kept. After merging main into a branch that touched
  `log.md`, scan the top section — same-line edits can duplicate lines (dedupe by hand;
  MD024 flags duplicate headings). The driver is for append-only files only; never extend it
  to `index.md` or any file that sees deletions.
- Tables: pipes need not visually align to the header (the config allows consistent style);
  do not hand-align them. Wrap bare record and field signatures in backticks (`` `NPC_ WNAM` ``)
  — raw `NPC_ WNAM` trips markdownlint MD037 (parsed as emphasis). Do not start a wrapped
  prose line with `+`, `-`, or `*` (parsed as a list item, MD004). `make format` autofixes
  most markdown but not these two.

## Maintenance obligations

- Any add or material change -> entry in `docs/log.md` (newest first) plus a listing in
  `docs/index.md`, same commit.
- `docs/` holds knowledge, never open work. Open work is GitHub issues and milestones
  (`AGENTS.md` "Roadmap and open work"). Item done -> the PR closes its issue
  (`Closes #NNN`), folds the learning into the wiki, and records it in `log.md`. No roadmap
  file, no "Done" sections, no checklists to hand-edit.
- Machine-specific or third-party state that will expire goes in `docs/tools/environment.md`
  with its observation date, never inline in a subsystem page or a skill.
- Reverse-engineered format -> byte layout and reference in `docs/formats/<name>.md`.
