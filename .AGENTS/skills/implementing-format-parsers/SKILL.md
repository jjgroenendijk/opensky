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
2. Reimplement from the spec and observed behavior only. A guessed byte layout is wrong
   more often than not, and Bethesda code or decompiles are off limits (root `AGENTS.md`,
   Legal & IP boundary).
3. A format already documented in `docs/formats/<name>.md` with its citation is the primary
   source — trust it, and re-pull upstream only to extend past it.
4. Fetching upstream specs has known access quirks (blocked hosts, non-default branches) that
   cost time every session — check `docs/tools/environment.md` before fighting a 403 or a 404.

## Model files

Copy the shape of an existing format rather than inventing one:

- Binary container: `Sources/OpenSkyFormatsCore/BSA/BSAArchive.swift`, its fixture
  `Tests/FormatsCoreTesting/BSA/BSAFixture.swift`, its tests
  `Tests/OpenSkyFormatsCoreTests/BSA/BSAArchiveTests.swift`, and `docs/formats/bsa.md`.
- ESM record: `Sources/OpenSkyFormatsESM/ESM/Records/Footstep.swift`, its tests
  `Tests/OpenSkyFormatsESMTests/ESM/Records/FootstepRecordTests.swift`, its real-data check
  `Tests/OpenSkyRealDataTests/Formats/ESM/Records/FootstepRealDataTests.swift`, and
  `docs/formats/footstep.md`.

## Writing it

- Cite the spec in a comment at the parse site and in the commit body.
- Clean Swift types decoupled from on-disk layout; `throws` plus typed errors; no
  force-unwrap, force-try, or force-cast on external data (hard lint errors).
- Validate defensively — real files carry mod quirks, and malformed input must not crash the
  engine. Unknown field or variant -> skip and note, not trap.
- Comment the why and the spec reference for non-obvious byte math, not the what.

## Testing

- The parser goes in `Sources/OpenSkyFormats<Family>/<Format>/`, in the family module the format
  belongs to (`docs/tools/modules.md` lists them). It imports only `OpenSkyFormatsCore`, never
  another family or engine code; see the same page for `public` access, explicit
  `public init(...)`, and `Sendable`.
- Unit-test in the matching `Tests/OpenSkyFormats<Family>Tests/<Format>/` folder with synthetic
  fixtures built in code (existing patterns: `BSAFixture`, `ESMFixture`, `NIFFixture`,
  `StringTableFixture`, in the `Tests/Formats<Family>Testing/` libraries). A test that also
  builds engine state goes in the test target of the highest module it imports
  (`Tests/AGENTS.md`). An extracted game file is never a fixture, not even a tiny one.
- Verify against the real install via an env-gated probe (load the `probing-real-game-data`
  skill) or `make run-cli ARGS=...`; probes never land in commits.

## Same-commit obligations

- `docs/formats/<name>.md` — byte layout, the spec used, and how the layout was confirmed
  on the real install (load the `writing-wiki-docs` skill first).
- Item came from a roadmap issue -> close it from the PR body (`Closes #NNN`).
