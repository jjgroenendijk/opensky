---
name: format-parser
description: Reverse-engineer + implement a game file format - spec citation rules,
  probe discipline, synthetic fixtures, doc template, defensive parsing. Use when
  adding or changing any parser for Skyrim SE file formats (ESM records, BSA, NIF,
  DDS, LOD, ...).
---

# Implementing a file format

Workflow companion to root `AGENTS.md` (Legal & IP + reverse-engineering sections
are the contract; this is the how).

## Before writing the parser

1. Find the open spec: UESP wiki, xEdit (SSEEdit) source (`wbDefinitionsTES5.pas`
   et al.), NifTools `nif.xml`, libbsa/BSArch notes, Papyrus docs. No spec ->
   write a small documented probe (load `probe` skill), record findings, flag the
   uncertainty in code + doc.
2. Never guess byte layouts. Never consult Bethesda code/decompiles. Reimplement
   from spec + observed behavior only.

## Writing it

- Cite the spec in a comment at the parse site and in the commit body.
- Clean Swift types decoupled from on-disk layout; `throws` + typed errors; no
  force-unwrap/try/cast on external data (hard lint errors).
- Validate defensively — real files carry mod quirks; malformed input must not
  crash the engine. Unknown field/variant -> skip + note, not trap.
- Comment the why + spec reference for non-obvious byte math, not the what.

## Testing

- Unit-test in `openskyTests/` with synthetic fixtures built in code (existing
  patterns: `BSAFixture`, `ESMFixture`, `NIFFixture`, `StringTableFixture`).
  NEVER check in extracted game files — not even tiny ones.
- Verify against the real install via env-gated probe (`probe` skill) or
  `make run-cli ARGS=...`; probes never land in commits.

## Same-commit obligations

- `docs/formats/<name>.md` — byte layout + reference used (`docs-wiki` skill for
  OKF frontmatter shape).
- `docs/index.md` entry + `docs/log.md` entry.
- Item came from `docs/todo.md` -> delete it there in the same commit.
