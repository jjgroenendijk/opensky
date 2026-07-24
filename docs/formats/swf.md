---
type: File Format
title: SWF container (FWS/CWS)
description: On-disk layout of SWF UI files and how OpenSky frames the tag stream.
tags: [format, swf, ui, scaleform]
timestamp: 2026-07-24T00:00:00Z
---

# SWF container (FWS/CWS)

Skyrim's interface is authored in Adobe SWF and played back by Scaleform GFx.
This milestone decodes the container only: signature and compression, the fixed
header fields, and the flat tag stream. Interpreting individual tag bodies —
shapes, fonts, text, the display list — is deferred to milestones 8.2.2 through
8.2.4.

Reference: Adobe SWF File Format Specification, version 19 (public Adobe
document). Impl: `opensky/Formats/SWF/`. All byte-aligned integers are
little-endian; the FrameSize RECT is bit-packed most-significant-bit first.

## Header — first 8 bytes, uncompressed

| offset | type  | field      | notes                                  |
| ------ | ----- | ---------- | -------------------------------------- |
| 0x00   | char3 | Signature  | `FWS`, `CWS`, or `ZWS` (below)         |
| 0x03   | uint8 | Version    | SWF version                            |
| 0x04   | uint32| FileLength | uncompressed total, includes this header |

The three signatures select body compression:

* `FWS` — uncompressed. The body follows the header verbatim.
* `CWS` — the body (everything after byte 8) is one zlib stream (RFC 1950, with
  the CMF/FLG header). Introduced with SWF 6. Its decompressed size is
  `FileLength - 8`. OpenSky decodes it through `opensky/Formats/Zlib.swift`,
  which validates CMF/FLG and the output length.
* `ZWS` — LZMA-compressed body (SWF 13+). Recognized but not decoded at this
  stage; it raises `SWFError.unsupportedCompression`.

An unknown signature raises `SWFError.notASWF`; a `FileLength` below 8 raises
`SWFError.invalidFileLength`. The header's first eight bytes are always read
uncompressed — only the body past byte 8 is compressed.

## Header body — after decompression

Parsed from the (decompressed) body, in order:

1. FrameSize — a RECT giving the stage bounds in twips (1/20 px). Bit-packed
   MSB-first: `Nbits = UB[5]`, then `Xmin`, `Xmax`, `Ymin`, `Ymax`, each a
   signed `SB[Nbits]`. The stream byte-aligns after the RECT.
2. FrameRate — `UI16` little-endian read as 8.8 fixed point: the frame rate is
   the stored value divided by 256.
3. FrameCount — `UI16` little-endian, number of frames in the main timeline.

The bit-packed reads go through `SWFBitReader` (`readUB` / `readSB`), the only
MSB-first bit reader in the repo; byte-aligned reads use the shared
`BinaryReader`.

## Tag stream

The body after the header fields is a flat sequence of tags. Each begins with a
RECORDHEADER:

* `UI16` little-endian. Tag code = `value >> 6`; length = `value & 0x3F`.
* A length of `0x3F` is the "long" form: the real length follows as a `UI32`
  little-endian.
* The body is exactly that many bytes and is left undecoded at this stage.

The stream terminates at the End tag (code 0, length 0), which OpenSky keeps as
the final entry in the tag list. Bytes after the End tag are ignored. A record
header or body that runs past the end of the data raises a typed error
(`BinaryReaderError` / `SWFBitReaderError`) rather than crashing or over-reading.

## Known-tag table

`SWFTagName.name(forCode:)` maps standard Adobe tag codes to their names (End=0,
ShowFrame=1, DefineShape=2, ... EnableTelemetry=93), and `isKnown` reports
whether a code is in the Adobe specification. This drives a known/unknown tally
when sweeping the game's `.swf` files.

Scaleform GFx adds its own extension tags in roughly the 1000+ code range. Those
are deliberately not part of the Adobe specification and stay "unknown" here;
decoding them is out of scope for the container milestone.

## Not implemented (yet)

* `ZWS` (LZMA) body decompression.
* Any tag-body decoding: shapes, fonts, text, bitmaps, the display list, and
  ActionScript / GFx extension tags.

## Verification

Unit tests: synthetic in-code fixtures (`openskyTests/SWFFileTests.swift`,
`openskyTests/SWFFixture.swift`) cover FWS field parsing, CWS round-trip, short
and long tags, End-tag termination with trailing bytes, unknown-tag passthrough,
the tag-name table, and rejection of bad signatures, `ZWS`, truncated headers,
truncated tag bodies, and a RECT running past the end.

`openskycli swf sweep` ([CLI dev tool](/tools/cli.md)) is the milestone 8.2.1 gate:
every archive/loose path under `interface\` ending `.swf` parsed through
`SWFFile`, with a known/unknown tag-code tally over `SWFTagName`.

## Vanilla sweep results

`openskycli swf sweep` against the vanilla install (`Skyrim - Interface.bsa`):
53 `.swf` movies, all 53 parsed (0 `ZWS`/unsupported, 0 failed). 14,477 tags
total, all 14,477 known to the Adobe tag table — no unknown or GFx-extension
(~1000+) tag codes appeared in vanilla `Interface/*.swf`. Versions observed:
mostly SWF 15, with `racesex_menu.swf` at version 8 and `fonts_pl.swf` /
`fonts_ru.swf` / `gfxfontlib.swf` / `sharedcomponents.swf` at version 10. Full
per-file output: `logs/swf-sweep.log` (gitignored, not committed — AGENTS.md
Legal & IP; reproduce with `openskycli swf sweep`).
