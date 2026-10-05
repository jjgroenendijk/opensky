---
type: File Format
title: SWF container (FWS/CWS)
description: SWF header, compression, and tag stream framing, with the vanilla Interface
  movie census.
tags: [format, swf, ui, scaleform]
---

# SWF container (FWS/CWS)

Skyrim's interface is made of Adobe SWF movies, played by Scaleform GFx. This page covers
the file container: the header, the compression, and the tag stream. The tags themselves
are on four more pages:

- [SWF shapes and bitmaps](/formats/swf-shapes.md)
- [SWF fonts and text](/formats/swf-text.md), including `fontconfig.txt`
- [SWF display list](/formats/swf-display-list.md), including labels, exports, and imports
- [SWF actions](/formats/swf-actions.md), the ActionScript 1/2 bytecode

The GPU side is on [screen-space UI layer](/rendering/ui.md). The bytecode runtime is on
[AS2 runtime](/engine/as2-runtime.md).

Reference: Adobe SWF File Format Specification, version 19 (a public Adobe document). All
byte-aligned integers are little-endian. Bit fields are packed most significant bit first.

## Header

The first 8 bytes are never compressed:

| offset | type | field | notes |
| --- | --- | --- | --- |
| 0x00 | char[3] | Signature | `FWS`, `CWS`, or `ZWS` |
| 0x03 | uint8 | Version | SWF version |
| 0x04 | uint32 | FileLength | total size after decompression, header included |

The signature picks the compression of everything after byte 8:

- `FWS`: not compressed.
- `CWS`: one zlib stream (RFC 1950, with the CMF/FLG header), from SWF 6. It decompresses
  to `FileLength - 8` bytes.
- `ZWS`: LZMA, from SWF 13. OpenSky does not decode it. Vanilla does not use it.

After decompression, the body starts with three fields:

1. FrameSize: a RECT with the stage bounds in twips (1/20 pixel). `Nbits = UB[5]`, then
   `Xmin`, `Xmax`, `Ymin`, `Ymax` as `SB[Nbits]`. The stream aligns to a byte after it.
2. FrameRate: `UI16`, 8.8 fixed point. The frame rate is the value divided by 256. AS2
   timers use it to turn milliseconds into frames.
3. FrameCount: `UI16`, the number of frames in the main timeline.

## Tag stream

The rest of the body is a flat list of tags. Each tag starts with a RECORDHEADER:

- `UI16`: tag code is `value >> 6`, length is `value & 0x3F`.
- A length of `0x3F` means the long form: the real length follows as a `UI32`.
- The tag body is exactly that many bytes.

The End tag (code 0, length 0) ends the stream. Bytes after it are ignored. A DefineSprite
body holds its own tag stream with the same framing.

Scaleform GFx adds its own tags, with codes around 1000 and above. They are not in the Adobe
specification. Vanilla uses none of them.

## Vanilla movies

`Skyrim - Interface.bsa` has 53 `.swf` movies. All parse. None uses `ZWS`.

- 14,477 tags in total. Every tag code is in the Adobe table.
- Most movies are SWF 15. `racesex_menu.swf` is version 8. `fonts_pl.swf`, `fonts_ru.swf`,
  `gfxfontlib.swf`, and `sharedcomponents.swf` are version 10.
- 1,032 of the 1,902 frame-1 draws have alpha 0 through their color transform. Vanilla
  menus hide most content at frame 1 and show it from ActionScript. So a correct frame-1
  render of many movies is empty: 20 of the 53 movies change no pixels, and 10 of them
  (font libraries and asset-only movies) draw nothing at all.

`openskycli swf sweep` decodes every tag in every movie and prints the counts.
`openskycli swf render-sweep` renders frame 1 of each movie. `openskycli swf action-sweep`
counts the bytecode. See [CLI](/tools/cli.md). Their logs and captures go to `.logs/` only,
because a rendered vanilla movie contains game art.

## Not implemented

- `ZWS` (LZMA) decompression.
- Stroke geometry for line styles.
- HTML text layout in DefineEditText.
- `Ratio` morph shapes and button states.
- PlaceObject3 filters and blend modes (decoded and counted, not applied).
- DoABC (82), ActionScript 3, and GFx extension tags.
