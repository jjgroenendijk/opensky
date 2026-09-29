---
name: writing-wiki-docs
description: Writes and updates pages under docs/ - what belongs in a page and what belongs
  in code or git, the plain writing style, page frontmatter, links, and the length limit.
  Use whenever adding, changing, or deleting anything under docs/.
---

# Writing docs

A docs page holds what the code cannot show. Everything else lives somewhere better:

| Content | Where it lives |
| --- | --- |
| Who changed what, when, in which issue or milestone | `git log`, merged PRs, closed issues |
| What a type or function does | Its name, its types, a short doc comment |
| Which tests cover something | The test files. `grep -rl TypeName Tests` finds them |
| Milestone acceptance records | The PR or issue that closes the milestone |
| Open work and plans | GitHub issues and milestones |
| Numbers that change with the next commit (counts, timings) | Nowhere. Measure them when needed |
| Facts about this machine that will expire | `docs/tools/environment.md`, with the date observed |

## What belongs in a page

- **Where a fact comes from.** Spec links, and how a byte layout was confirmed.
- **Why a design was chosen**, when the reason is not visible in the code.
- **Where OpenSky differs from the original game**, and why.
- **How several subsystems work together**, when no single file shows it.
- **How to use the tools and the build.**

Keep every reverse-engineered fact and every spec citation. They are expensive to find
again. If a fact is only about one parser or type, put it in a doc comment there instead.

## Writing style

Use the writing style in the root `AGENTS.md`. A docs page adds one rule: no
`## Contents` list, because the headings are enough.

Bad:

> Issue #104 (M2.1, item 2.1.3) added `BSAArchive.open(url:)`, which reads the header and
> then calls `readFolderRecords()`. `BSAArchiveTests` covers it. Opening all vanilla
> archives takes 378 ms in Debug.

Good:

> Skyrim SE uses BSA version 105. Each folder record is 24 bytes. The original Skyrim used
> version 104, with 16-byte folder records and zlib compression. OpenSky does not read
> version 104. Source: the UESP page "Skyrim Mod:Archive File Format".

The bad version gives history, repeats the code, lists tests, and gives a timing that will
change. The good version gives facts and their source.

## Page shape

`docs/formats/bsa.md` is a model page: a spec citation, byte layout tables, and what was
confirmed on the real install. Its frontmatter and opening look like this:

```markdown
---
type: File Format
title: BSA Archive
description: On-disk layout of Skyrim SE .bsa archives and how OpenSky reads them.
---

# BSA archive

One or two sentences: what this is.

Reference: <spec link>. All integers are little-endian.

## Header

Byte layout table, then what was confirmed on the real install.
```

- Frontmatter needs `type`, `title`, and `description`. `tags` is optional. Do not add a
  `timestamp`; git records dates.
- Group pages by folder: `formats/`, `engine/`, `rendering/`, `decisions/`, `tools/`.
- Inside `docs/`, link from the docs root: `[BSA](/formats/bsa.md)`. Outside `docs/`, use a
  repository path: `docs/formats/bsa.md`.
- Write a record or field signature in backticks: `` `NPC_ WNAM` ``. Without them,
  markdownlint reads the underscore as emphasis (rule MD037).

## Checks

`make check` runs these, and the pre-commit hook runs them on staged pages:

- `make md-lint`: Markdown style.
- `make docs-links`: every link inside `docs/` points at a file that exists.
- `make docs-length`: no page is longer than the limit in `tools/lint/docs-length.sh`. A
  page over the limit is split by topic, or cut. Do not raise the limit.
