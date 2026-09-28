---
type: File Format
title: SWF container (FWS/CWS)
description: SWF UI file framing - signature and compression, header fields, and the tag stream -
  with links to the pages for shapes, text, the display list, and actions.
tags: [format, swf, ui, scaleform]
---

# SWF container (FWS/CWS)

Skyrim's interface is made in Adobe SWF (Flash) and played by Scaleform GFx. A menu is one
`.swf` movie under `interface\`. This page covers the file framing. The other SWF pages:

- [SWF shapes and bitmaps](/formats/swf-shapes.md): vector shapes, tessellation, and images.
- [SWF fonts and text](/formats/swf-text.md): fonts, text fields, and `fontconfig.txt`.
- [SWF display list](/formats/swf-display-list.md): placing objects, sprites, frame labels,
  exports, and imports.
- [SWF actions](/formats/swf-actions.md): ActionScript 1 and 2 bytecode and clip events.

Drawing is on the [SWF render layer](/rendering/swf-layer.md) page. Running the bytecode is on the
[ActionScript 2 runtime](/engine/as2-runtime.md) page.

Source: the Adobe SWF File Format Specification, version 19. Page numbers on the SWF pages refer
to it. Byte-aligned integers are little-endian. Bit fields are read most significant bit first.

## Header (first 8 bytes, never compressed)

| Offset | Type | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 3 chars | Signature | `FWS`, `CWS`, or `ZWS` |
| 0x03 | uint8 | Version | SWF version |
| 0x04 | uint32 | FileLength | Total size after decompression, header included |

The signature picks the compression of everything after byte 8:

- `FWS`: none.
- `CWS`: one zlib stream (RFC 1950, with its 2-byte header), from SWF 6. It unpacks to
  `FileLength - 8` bytes.
- `ZWS`: LZMA, from SWF 13. OpenSky does not decode it and reports "unsupported compression".

Any other signature is "not a SWF". A `FileLength` below 8 is an error.

## Header body

After decompression, in order:

1. FrameSize: a RECT with the stage size in twips (1/20 pixel). A RECT is `Nbits` (5 bits),
   then `Xmin`, `Xmax`, `Ymin`, `Ymax`, each a signed field of `Nbits` bits. The reader moves to
   the next whole byte after it.
2. FrameRate: a uint16 in 8.8 fixed point, so frames per second is the value / 256. The
   ActionScript timers need it to turn milliseconds into frames.
3. FrameCount: a uint16, the frames in the main timeline.

## Tag stream

The rest is a flat list of tags. Each starts with a record header:

- A uint16. Tag code = `value >> 6`. Length = `value & 0x3F`.
- A length of `0x3F` means the real length follows as a uint32.
- The body is exactly that many bytes.

The End tag (code 0, length 0) ends the stream. Bytes after it are ignored. A header or body that
runs past the end of the data is an error, not a crash.

The tag name table has every code in the Adobe specification, from End (0) to EnableTelemetry
(93). Scaleform adds its own tags at about 1000 and above. OpenSky treats them as unknown.

## Vanilla facts

- `Skyrim - Interface.bsa` has 53 movies, and all of them parse. Every tag in them is a known
  Adobe tag. There are no Scaleform tags and no `ZWS` files.
- Most movies are SWF 15. `racesex_menu.swf` is version 8. `fonts_pl.swf`, `fonts_ru.swf`,
  `gfxfontlib.swf`, and `sharedcomponents.swf` are version 10.
- Most menus hide their content at frame 1 through a color transform with alpha 0, and show it
  from ActionScript. So a correct frame-1 drawing of many movies is blank. `book.swf` and
  `loadingmenu.swf` are clear examples.

## Not implemented

- `ZWS` (LZMA) decompression.
- Line (stroke) geometry. Line styles are decoded, but not turned into triangles.
- HTML text layout. The markup is kept, and a plain-text version is drawn.
- Morph shapes (`Ratio`) and button states.
- PlaceObject3 filters and blend modes. They are read and counted, but not drawn.
- DoABC (82), which is ActionScript 3.

## Tools

- `openskycli swf sweep` decodes every movie: tags, shapes, bitmaps, fonts, text, and frame-1
  display lists. Any decode failure fails the sweep.
- `openskycli swf render-sweep` draws frame 1 of each movie offscreen with the real renderer.
  Add `--movie <name>` to draw one movie with a fresh glyph atlas.
- `openskycli swf action-sweep` counts opcodes, action blocks, clip events, and the names the
  bytecode calls.

See [CLI](/tools/cli.md). The same numbers show in the app at Developer > UI Lab > SWF movie.
Output goes to `logs/`, because a rendered menu contains game art.
