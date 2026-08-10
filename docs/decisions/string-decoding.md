---
type: Decision
title: Engine-wide game-data string decoding
description: One lenient policy for every string read out of game data — UTF-8, then
  windows-1252, then ISO 8859-1, never a failure — and the narrow strict exception.
tags: [decision, formats, text, encoding, localization]
timestamp: 2026-08-10T00:00:00Z
---

# String decoding for game data

Binding for every parser that turns bytes from the user's install into text: BSA names,
ESM/plugin fields, VMAD script data, NIF string tables, PEX string tables, SWF strings,
localized string tables, and INI files. Resolves GitHub issue #72, which recorded the
inconsistency: BSA and VMAD assumed windows-1252, PEX and parts of SWF assumed UTF-8, NIF
and the string tables already had a fallback chain, and each site chose its own failure
behavior.

## Decision

One policy, `GameText.decode(_:)` in `opensky/Engine/Formats/GameText.swift`:

1. Valid UTF-8 -> decode as UTF-8.
2. Otherwise decode as windows-1252.
3. Otherwise decode as ISO 8859-1.

The function is total. It returns a `String` for every byte sequence, including empty
input, and there is no failure path a caller has to handle.

`BinaryReader.readZString`, `readBZString` and `readBString` take this policy by default,
so a parser gets it without asking. Reads that want a different rule pass a
`TextDecoding` explicitly.

## Why this order

* **UTF-8 first.** Vanilla files are windows-1252, but mod tools increasingly write UTF-8,
  and nothing in any of these formats carries an encoding marker. UTF-8 is self-validating:
  a multi-byte sequence has a shape a run of legacy high bytes almost never matches by
  accident, so "decodes as UTF-8" is strong evidence the bytes *are* UTF-8. The reverse
  test does not exist — every byte string is *some* legacy codepage text.
* **windows-1252 second.** It is what the Creation Kit wrote and what vanilla English,
  French, German, Italian, Spanish and Polish data contains. ASCII, the overwhelming
  majority of names and paths, decodes identically under all three tiers, so the tier only
  matters for accented text.
* **ISO 8859-1 last.** windows-1252 leaves five bytes undefined (0x81, 0x8D, 0x8F, 0x90,
  0x9D). Vanilla NIF string tables contain them as exporter junk — uninitialized memory in
  a name field. ISO 8859-1 maps all 256 byte values, which is what makes the chain total.

## Why never throw

A name is not the asset. A mis-encoded folder name inside a BSA, or an editor ID in a
mod's plugin, is a cosmetic defect in one string; failing the read would drop the archive,
record, or mesh that carries it and take working content down with it. Mojibake in one
string is recoverable and visible; a lost archive is neither.

The other half of issue #72 — "must never silently corrupt lookups" — is handled by
normalization rather than by decode: BSA and VFS paths are lowercased and separator-folded
before lookup ([VFS](/formats/vfs.md)), so both the archive side and the request side of a
comparison run through the same decode and the same folding. A wrong-encoding name still
matches itself.

Bounds, framing and length prefixes stay strict. Only the bytes-to-text step is lenient:
`BinaryReaderError.outOfBounds` and `.unterminatedString` are unaffected, and a string
whose length prefix runs past the end of the buffer still throws.

## The strict exception

`TextDecoding.strict(_:)` decodes under exactly one encoding and throws
`BinaryReaderError.invalidString` when the bytes fall outside it. Reserved for structural
fields whose encoding the format itself pins down, where garbage means the file is not
what it claims to be rather than that an author typed an accent:

* Havok type and version names, ASCII by the container's own layout
  ([HKX container](/formats/hkx-container.md)).
* Four-character record and chunk tags, which have their own ASCII readers
  (`FourCC`, `SWFFile`, `HKXHeader`).

OpenSky's own save format is not game data: it is written and read by this engine, so it
stays strict UTF-8 ([OpenSky save](/formats/opensky-save.md)).

## Consequences

* `GameText.decodeLossy` is gone; `GameText.decode` absorbed it and lost its optional
  return.
* `PexError.invalidString` and `ScriptDataError.invalidString` are gone — nothing can raise
  them any more. Callers that pattern-matched them handled a case that cannot occur.
* Localized string table lookup no longer throws on undecodable bytes
  ([strings](/formats/strings.md)); it still throws on framing that leaves the data block.
* Text written back out is unchanged: `BinaryWriter.writeZString` still takes an explicit
  encoding and still throws on an unencodable string, because when writing we choose the
  encoding and an unrepresentable character is a real error.

## Verification

`openskyTests/GameTextTests.swift` covers all three tiers, the cp1252-before-Latin-1
ordering, totality over lone surrogates, truncated UTF-8 and all 256 byte values, and the
strict rejection path. `openskyTests/BinaryReaderTests.swift` covers the three reader
entry points against a byte windows-1252 leaves undefined.
