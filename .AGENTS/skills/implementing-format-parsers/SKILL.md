---
name: implementing-format-parsers
description: Reverse-engineers and implements a Skyrim SE file format - spec citation rules,
  probe discipline, the module a parser goes in, pure parsing with typed errors, synthetic
  fixtures, and the docs/formats page. Use when adding or changing any parser for ESM
  records, BSA, NIF, DDS, HKX, PEX, SWF, audio, or LOD data.
---

# Implementing a file format

The root `AGENTS.md` section "Legal & IP boundary" is the contract. This skill is the how.

## Workflow

1. Find the source of the layout.
2. Pick the module and copy a model file.
3. Write a pure parser.
4. Test it with synthetic fixtures, then check it on the real install.
5. Write the `docs/formats/` page in the same commit.

## 1. Find the source

- A format with a page in `docs/formats/` is already cited and confirmed. Trust the page,
  and go upstream only to extend past it.
- Otherwise use an open spec: the UESP wiki, xEdit (SSEEdit) `wbDefinitionsTES5.pas`,
  NifTools `nif.xml`, BSArch notes, the Papyrus docs. Note the exact version or commit
  you read, because the page cites it.
- No spec covers it -> do not guess. A guessed byte layout is wrong more often than not.
  Write a probe (`probing-real-game-data` skill), and flag the uncertainty in the page.
- Bethesda code, decompiles, and SKSE internals are off limits.
- Upstream hosts have access quirks (blocked hosts, non-default branches). Check
  `docs/tools/environment.md` before fighting a 403 or a 404.

## 2. Pick the module and a model

Each format family is one module, and it imports only `OpenSkyFormatsCore`
(`docs/tools/modules.md` lists the families; `make module-graph` fails on another import).
The parser goes in `Sources/OpenSkyFormats<Family>/<Format>/`.

Copy the shape of an existing format:

| Kind | Parser | Fixture | Unit tests | Page |
| --- | --- | --- | --- | --- |
| Binary container | `Sources/OpenSkyFormatsCore/BSA/BSAArchive.swift` | `Tests/FormatsCoreTesting/BSA/BSAFixture.swift` | `Tests/OpenSkyFormatsCoreTests/BSA/BSAArchiveTests.swift` | `docs/formats/bsa.md` |
| ESM record | `Sources/OpenSkyFormatsESM/ESM/Records/Footstep.swift` | `ESMFixture` in `Tests/FormatsESMTesting/` | `Tests/OpenSkyFormatsESMTests/ESM/Records/FootstepRecordTests.swift` | `docs/formats/footstep.md` |

The real-data check of the record model is
`Tests/OpenSkyRealDataTests/Formats/ESM/Records/FootstepRealDataTests.swift`.

## 3. Write a pure parser

Parsers are pure: bytes or a record in, values out. The model files show each rule.

- The parse entry point takes `Data` or an `ESMRecord`: `BSAArchive.init(data:)`,
  `Footstep.init(record:)`. A file-reading `init(url:)` only loads the bytes and calls it.
  No clocks, Metal, audio, or engine state.
- Read bytes with `BinaryReader` from `OpenSkyFormatsCore/Binary/`. Do not hand-roll
  offset math on `Data`.
- Return clean Swift types, not a copy of the on-disk struct.
- Fail with `throws` and the family's typed error (`BSAError`, `ESMError`). A force-unwrap,
  force-try, or force-cast is a SwiftLint error, so `make check` catches it.
- Real files carry mod quirks, and malformed input must not crash the engine. An unknown
  field, block, or variant is skipped and counted, not trapped. A record with many skip
  reasons counts them in a `SkipTally` (`PerkSkipKind` in `Perk.swift` is the model), so a
  test can assert on what was skipped.
- Types are `nonisolated public` and `Sendable`, with an explicit `public init(...)` where
  another module builds them (`Sources/AGENTS.md`, Swift conventions).

Comments stay short (root `AGENTS.md`, Writing style). The file header says what the format
is in a line or two and links its page, like `Footstep.swift`. A non-obvious byte step gets
a one-line why. The spec links and the evidence go in the page, not in the code.

## 4. Test it

- Build fixtures in code in the family's testing library, `Tests/Formats<Family>Testing/`.
  An extracted game file is never a fixture, not even a tiny one, and not a cut-down copy
  of a mod file.
- Put the suite in `Tests/OpenSkyFormats<Family>Tests/<Format>/` with
  `@Suite(.tags(.parser))`. `make lint-test-tags` checks the tag. A suite that also builds
  engine state goes in the test target of the highest module it imports (`Tests/AGENTS.md`).
- A bug fix starts with a fixture that reproduces it and a test that fails.
- Run `make test-unit T='OpenSkyFormats<Family>Tests/<Suite>'` while working, then
  `make test-parser` before pushing.
- Check the layout on the real install with `make run-cli ARGS=...` or a real-data suite
  under `Tests/OpenSkyRealDataTests/Formats/`, run by `make test-real`. A throwaway probe
  never lands in a commit.

## 5. The docs page

Write or extend `docs/formats/<name>.md` in the same commit (`writing-wiki-docs` skill):
the spec and version used, the byte layout, and how the layout was confirmed on the real
install. Cite the spec in the commit body too.
