---
name: implementing-format-parsers
description: Reverse-engineers and implements a Skyrim SE file format - spec citation rules,
  probe discipline, synthetic fixtures, the documentation template, and defensive parsing.
  Use when adding or changing any parser for ESM records, BSA, NIF, DDS, or LOD data.
---

# Implementing a file format

Root `AGENTS.md` "Legal & IP boundary" is the contract; this is the how. Reverse-engineering
discipline lives here, not there.

## Before writing the parser

1. Find the open spec: UESP wiki, xEdit (SSEEdit) source (`wbDefinitionsTES5.pas` et al.),
   NifTools `nif.xml`, libbsa and BSArch notes, Papyrus docs. No spec -> write a small
   documented probe (load the `probing-real-game-data` skill), record findings, and flag the
   uncertainty in code and doc.
2. Never guess byte layouts. Never consult Bethesda code or decompiles. Reimplement from spec
   and observed behavior only.
3. A format already documented in `docs/formats/<name>.md` with its citation is the primary
   source — trust it, and re-pull upstream only to extend past it.
4. Fetching upstream specs has known access quirks (blocked hosts, non-default branches) that
   cost time every session — check `docs/tools/environment.md` before fighting a 403 or a 404.

## Writing it

- Cite the spec in a comment at the parse site and in the commit body.
- Clean Swift types decoupled from on-disk layout; `throws` plus typed errors; no
  force-unwrap, force-try, or force-cast on external data (hard lint errors).
- Validate defensively — real files carry mod quirks, and malformed input must not crash the
  engine. Unknown field or variant -> skip and note, not trap.
- Comment the why and the spec reference for non-obvious byte math, not the what.

## Testing

- Unit-test in `openskyTests/` with synthetic fixtures built in code (existing patterns:
  `BSAFixture`, `ESMFixture`, `NIFFixture`, `StringTableFixture`, all under
  `openskyTestSupport/`). NEVER check in extracted game files — not even tiny ones.
- Verify against the real install via an env-gated probe (load the `probing-real-game-data`
  skill) or `make run-cli ARGS=...`; probes never land in commits.

## Same-commit obligations

- `docs/formats/<name>.md` — byte layout and reference used (load the `writing-wiki-docs`
  skill for the OKF frontmatter shape).
- `docs/index.md` entry plus `docs/log.md` entry.
- Item came from a roadmap issue -> close it from the PR body (`Closes #NNN`).
