---
name: docs-wiki
description: Write or update the docs/ knowledge wiki - OKF v0.1 frontmatter,
  reserved files (index.md, log.md), link style, todo hygiene. Use whenever adding
  or materially changing anything under docs/.
---

# docs/ wiki — Open Knowledge Format

`docs/` follows Google Open Knowledge Format (OKF v0.1):
<https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md>.
Wiki holds reverse-engineered formats, subsystem design, decisions — knowledge
that must survive across sessions. Doc updates land in the same commit as the
change they document.

## File rules

- Bundle root `docs/`, plain tree of `.md`. Group by domain: `formats/`,
  `engine/`, `rendering/`, `decisions/`, `tools/`.
- Every non-reserved `.md` starts with YAML frontmatter, at least non-empty
  `type`. Recommended order: `title`, `description`, `resource`, `tags`,
  `timestamp` (ISO 8601):

  ```markdown
  ---
  type: File Format
  title: BSA Archive
  description: On-disk layout of Skyrim SE .bsa archives and how OpenSky reads them.
  tags: [format, archive, io]
  timestamp: 2026-07-09T00:00:00Z
  ---
  ```

- Concept ID = path minus `.md` (`docs/formats/bsa.md` -> `formats/bsa`).
- Reserved names, optional, any level: `index.md` (directory listing, no
  frontmatter, `* [Title](/path.md) - description` lines) and `log.md` (change
  history, newest first, ISO-8601 date headings).
- Links bundle-absolute from `docs/`: `[BSA](/formats/bsa.md)`. Broken links
  tolerated; relationship comes from prose.
- `log.md` merges with `merge=union` (root `.gitattributes`, issue #108):
  parallel PRs prepending entries merge clean, both kept. After merging main
  into a branch that touched `log.md`, scan the top section — same-line edits
  can duplicate lines (dedupe by hand; MD024 flags dup headings). Driver is
  for append-only files only; never extend it to `todo.md`/`index.md`.
- Tables: pipes need not visually align to the header (config allows consistent
  style); do not hand-align them. Wrap bare record/field signatures in backticks
  (`` `NPC_ WNAM` ``) — raw `NPC_ WNAM` trips markdownlint MD037 (parsed as
  emphasis). Do not start a wrapped prose line with `+`/`-`/`*` (parsed as a list
  item, MD004). `make format` autofixes most markdown but not these two.

## Maintenance obligations

- Any add/material change -> entry in `docs/log.md` (newest first) + listing in
  `docs/index.md`, same commit.
- `docs/todo.md` is open work only. Item done -> same commit deletes it there,
  folds learning into the wiki, records it in `log.md`. No "Done" sections.
- Reversed format -> byte layout + reference in `docs/formats/<name>.md`.
