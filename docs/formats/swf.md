---
type: File Format
title: SWF container (FWS/CWS)
description: On-disk layout of SWF UI files - container framing, shape tags with
  tessellation, bitmap/font/text tags, the display-list control tags, and the
  ActionScript 1/2 action records (framed and named, not executed).
tags: [format, swf, ui, scaleform]
timestamp: 2026-07-24T00:00:00Z
---

# SWF container (FWS/CWS)

Skyrim's interface is authored in Adobe SWF and played back by Scaleform GFx.
Milestone 8.2.1 decodes the container: signature and compression, the fixed
header fields, and the flat tag stream. Milestone 8.2.2 adds the shape
definition tags (with CPU tessellation) and the bitmap definition tags.
Milestone 8.2.3 adds the font tags (glyph extraction) and the static-text tags,
plus the Scaleform `fontconfig.txt` alias mapping. Milestone 8.2.4 adds the
display-list control tags, sprite timelines, and asset imports — everything the
renderer needs to draw a movie's first frame
([screen-space UI layer](/rendering/ui.md)). Milestone 8.3.1 adds the action
side: full timelines instead of frame 1 alone, DoAction/DoInitAction bytecode
framed and named, and PlaceObject2/3 CLIPACTIONS event handlers decoded. Nothing
in that bytecode is executed yet — 8.3.2 builds the interpreter on top.

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
   the stored value divided by 256. Retained on `SWFMovie` since milestone 8.3.2
   phase 3, because the AS2 timer natives convert a millisecond interval into
   ticks with it (see [AS2 runtime](/engine/as2-runtime.md)).
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

## Shape tags — DefineShape (2), DefineShape2 (22), DefineShape3 (32), DefineShape4 (83)

Reference: spec chapter 6 "Shapes" (pp. 119-133) and chapter 7 "Gradients"
(pp. 134-136). Impl: `opensky/Formats/SWF/SWFShape.swift` (tag layout,
`SWFShapeDefinition.parse(tag:)`), `SWFShapeParser.swift` (bit-level
structures), `SWFShapeTypes.swift` (style value types).

Tag body: `ShapeId` UI16, `ShapeBounds` RECT, then SHAPEWITHSTYLE.
DefineShape4 inserts `EdgeBounds` RECT plus a flag byte (Reserved UB[5],
`UsesFillWindingRule` UB[1] — SWF 10+, `UsesNonScalingStrokes`,
`UsesScalingStrokes`) between the bounds and the styles.

SHAPEWITHSTYLE = FILLSTYLEARRAY, LINESTYLEARRAY, `NumFillBits` UB[4],
`NumLineBits` UB[4], then shape records. Style arrays index from 1; index 0
means no fill / no stroke.

Per-version rules:

* Colors are RGB in DefineShape/DefineShape2 and RGBA in DefineShape3/4
  (FILLSTYLE, LINESTYLE, and GRADRECORD color fields alike).
* The 0xFF style-count escape to a UI16 extended count applies to DefineShape2
  and later (spec FILLSTYLEARRAY, p. 122); DefineShape reads 0xFF as a literal
  count of 255.
* DefineShape4 line styles are LINESTYLE2 (cap/join/scaling flags, optional
  8.8 miter limit, and either an RGBA color or a stroke FILLSTYLE); earlier
  versions use the width + color LINESTYLE.
* Focal radial gradients (fill type 0x13, FOCALGRADIENT with a FIXED8 focal
  point) belong to DefineShape4 per the spec; the parser accepts the type
  leniently in any version.

FILLSTYLE types: 0x00 solid, 0x10 linear gradient, 0x12 radial gradient, 0x13
focal radial gradient, 0x40/0x41/0x42/0x43 bitmap (repeating/clipped and
smoothed/non-smoothed variants; the fill carries a bitmap character id plus a
MATRIX).

Shape records are bit-packed and not byte-aligned: a TypeFlag bit selects
edge records (StraightEdgeRecord general/vertical/horizontal deltas,
CurvedEdgeRecord quadratic Bezier control + anchor deltas, both SB[NumBits+2])
or non-edge records (EndShapeRecord = six zero bits; StyleChangeRecord with
MoveTo — absolute, relative to the shape origin — FillStyle0/FillStyle1/
LineStyle selections read with the current index bit widths, and optional
replacement style arrays). `SWFShapeParser` flattens replacement arrays into
single global style lists and rebases the record indices, so a
`SWFShapeSegment` index is stable for the whole shape. A bare SHAPE (glyphs,
for 8.2.3) parses through `SWFShapeDefinition.parseGlyphSegments(_:)` with
pass-through indices.

Alignment notes (the spec marks RECT/MATRIX "must be byte aligned" but is
silent elsewhere): GRADIENT after the fill's MATRIX and the `NumFillBits`
field after the style arrays are both treated as byte-aligned. Observed
encoders agree — all 53 vanilla movies (2,677 shapes) parse cleanly under this
rule with zero failures.

## Shape tessellation

Impl: `opensky/Formats/SWF/SWFShapeTessellator.swift`. Output is
`SWFShapeMesh`: a twip-space triangle list (`[SIMD2<Float>]`, three vertices
per triangle) with `FillRun` ranges grouping triangles per fill style index.
`SWFShapeCache` memoizes the mesh per shape character id; 8.2.4's renderer
consumes this cache. GPU upload is out of scope for 8.2.2.

* Quadratic edges flatten deterministically: uniform subdivision with the step
  count derived from the control point's deviation from the chord midpoint
  (tolerance 1 twip, 64-step cap).
* FillStyle0 is the fill left of an edge's travel direction, FillStyle1 the
  right (spec p. 128). For each fill, fill1 edges enter the sweep forward and
  fill0 edges reversed, giving a consistently oriented boundary; an edge with
  the same fill on both sides cancels itself, so interior edges never split a
  fill.
* Triangulation is a horizontal-band trapezoid sweep (bands split at every
  segment endpoint y; spans selected by fill rule; two triangles per
  trapezoid, slivers dropped). Holes and disjoint contours need no contour
  chaining. The fill rule is even-odd by default and nonzero winding when
  DefineShape4 sets `UsesFillWindingRule`.
* Deferred: stroke tessellation. Line styles (including LINESTYLE2 caps,
  joins, and stroke fills) are fully decoded and carried on segments, but no
  stroke geometry is emitted yet — vanilla UI art is overwhelmingly
  fill-based, and stroke meshes need the 8.2.4 draw path to pick a pixel
  scale.

## Font tags — DefineFont2 (48), DefineFont3 (75)

Reference: spec chapter 10 "Fonts and Text" (pp. 176-182). Impl:
`opensky/Formats/SWF/SWFFont.swift` (value types),
`SWFFontParser.swift` (DefineFont2/3), `SWFFontCompanionParser.swift`
(companion tags).

Tag body: `FontID` UI16, a flag byte (`HasLayout`, `ShiftJIS`, `SmallText`,
`ANSI`, `WideOffsets`, `WideCodes`, `Italic`, `Bold`, MSB first), `LanguageCode`
UI8, a length-prefixed `FontName`, `NumGlyphs` UI16, then:

* OffsetTable — `NumGlyphs` entries plus a trailing `CodeTableOffset`, each
  UI32 when `WideOffsets` else UI16. All offsets are measured from the start of
  the OffsetTable (immediately after `NumGlyphs`). OpenSky slices each glyph's
  SHAPE from the body using these offsets rather than parsing sequentially, so
  any per-glyph padding is irrelevant.
* GlyphShapeTable — one bare SHAPE per glyph (NumFillBits/NumLineBits + shape
  records, no style arrays), decoded through
  `SWFShapeDefinition.parseGlyphSegments(_:)`; fill indices follow the glyph
  convention (0 = off, 1 = on).
* CodeTable — `NumGlyphs` character codes, UI16 when `WideCodes` else UI8.
* Layout (only when `FontFlagsHasLayout`): `FontAscent`/`FontDescent`/
  `FontLeading` SI16, a `FontAdvanceTable` of SI16 advances, a `FontBoundsTable`
  of bit-packed RECTs (one per glyph), then `KerningCount` UI16 and the
  KERNINGRECORDs (code pair sized by `WideCodes`, SI16 adjustment).

DefineFont3 is byte-identical to DefineFont2 except its glyph and layout
coordinates use a 20x-finer EM square (spec p. 179). The decoded font exposes
`unitsPerEM` (1024 for DefineFont2, 20480 for DefineFont3), so a consumer scales
any glyph coordinate by `emPixelSize / unitsPerEM` to reach pixels regardless of
tag version — the EM square equals one font-size unit.

Defensive cases: a device-font placeholder with `NumGlyphs == 0` omits the
OffsetTable, CodeTable, and layout entirely (observed in `hudmenu.swf`); it
decodes to an empty font rather than over-reading. Malformed offsets throw
`SWFFontError.glyphOffsetOutOfRange`; a truncated body throws the underlying
`BinaryReaderError` / `SWFBitReaderError`.

Companion tags decode minimally (`SWFFontCompanionParser`) and are retained but
not applied — OpenSky rasterizes glyphs through its own CoreGraphics coverage
path, so the FlashType hinting is parsed-and-ignored:

* DefineFontAlignZones (73): `FontID` UI16 and the `CSMTableHint` (UB[2]); the
  per-glyph ZONERECORD table (which needs the referenced font's glyph count to
  size) is kept raw.
* CSMTextSettings (74): `TextID`, `UseFlashType`, `GridFit`, and the
  `Thickness`/`Sharpness` FLOAT32 hints.
* DefineFontName (88): the full font name and copyright strings.

## Glyph rasterization

Impl: `opensky/Formats/SWF/SWFGlyphPath.swift`, plus
`UIGlyphAtlas.swfEntry(...)` — see [Screen-space UI layer](/rendering/ui.md) for
the atlas side. `SWFGlyphPath.makePath(segments:unitsPerEM:emPixelSize:)` builds
a CoreGraphics `CGPath` from a glyph's straight + quadratic edges, scaled by
`emPixelSize / unitsPerEM` and flipped from SWF's y-down glyph space to
CoreGraphics y-up with the baseline at the origin. The glyph fills even-odd per
SWF glyph semantics. An empty glyph (no segments) yields nil, drawing no quad.

## Static text tags — DefineText (11), DefineText2 (33), DefineEditText (37)

Reference: spec chapter 10 (pp. 173-177). Impl:
`opensky/Formats/SWF/SWFText.swift` (DefineText/2),
`SWFEditText.swift` (DefineEditText).

DefineText/DefineText2 body: `CharacterID` UI16, `TextBounds` RECT, `TextMatrix`
MATRIX, `GlyphBits` UI8, `AdvanceBits` UI8, then a run of TEXTRECORDs terminated
by a zero byte. Each TEXTRECORD's flag byte (byte-aligned) selects optional
state changes — font id + text height, color, x offset, y offset — applied in
that spec order, then `GlyphCount` UI8 and that many GLYPHENTRYs of
`GlyphIndex` UB[GlyphBits] + `GlyphAdvance` SB[AdvanceBits] (bit-packed; the next
record re-aligns). State fields absent from a record inherit the value carried
by earlier records. DefineText2 stores RGBA colors where DefineText stores RGB.
The glyph indices point into the record's active font's glyph table, so static
text lays out directly from the record data (no CoreText shaping).

DefineEditText body: `CharacterID` UI16, `Bounds` RECT, then a 16-bit flag word
(`HasText`, `WordWrap`, `Multiline`, `Password`, `ReadOnly`, `HasTextColor`,
`HasMaxLength`, `HasFont`, `HasFontClass`, `AutoSize`, `HasLayout`, `NoSelect`,
`Border`, `WasStatic`, `HTML`, `UseOutlines`, MSB first). Then, gated by the
flags: `FontID` (HasFont), `FontClass` STRING (HasFontClass), `FontHeight`
(HasFont or HasFontClass), `TextColor` RGBA (HasTextColor), `MaxLength`
(HasMaxLength), a layout block (align, margins, indent, leading — HasLayout), a
`VariableName` STRING, and `InitialText` STRING (HasText). STRINGs are
null-terminated UTF-8 (SWF 6+) with a CP1252 fallback. For static rendering the
plain-text content is the target: HTML fields keep the raw markup verbatim and
expose a tag-stripped `plainText`; full HTML text layout is deferred to 8.3.x.

Alignment note (as with shapes, the spec marks only RECT/MATRIX byte-aligned):
OpenSky byte-aligns before the DefineEditText flag word and treats it as two
whole bytes, which keeps the following UI16 fields aligned. All vanilla text
tags decode cleanly under this rule.

## fontconfig.txt (Scaleform GFx font mapping)

Impl: `opensky/Formats/SWF/SWFFontConfig.swift` (parser),
`SWFFontLibrary.swift` (resolver). The game ships `Interface/fontconfig.txt`,
read via the VFS (`vfs.contents(forPath: "interface\\fontconfig.txt")`). It maps
logical font aliases to font names defined inside fontlib movies.

This grammar is OBSERVED behavior, not a published specification (open GFx
documentation is thin) — the subset OpenSky implements:

* `fontlib "<Interface\movie.swf>"` — declare a movie whose fonts back the
  aliases. The name is an install-relative path (already carries the
  `Interface\` prefix in vanilla).
* `map "$Alias" = "FontName" [Style ...]` — map a logical alias (e.g.
  `$EverywhereFont`) to a font name, with optional trailing style keywords
  (`Normal`, `Bold`, `Italic`, ...) retained but not used for matching.
* `#` begins a comment to the end of the line (outside quotes); blank lines are
  ignored.

Any other non-empty line (e.g. vanilla's `mapdefault`, `validNameChars`) is
retained verbatim in `unrecognizedLines` and reported, never silently dropped —
the uncertainty is surfaced rather than guessed away.

Resolution: `SWFFontLibrary.register(movie:file:)` decodes a movie's
DefineFont2/3 tags and its ExportAssets (56) name table, indexing each font by
its export name and its internal font name. `resolve(alias:config:)` looks the
alias up in the config's `map` directives, then finds a registered font with
that name (exact, then case-insensitive). GFx font naming — whether a `map`
name matches an export name or an internal name — is itself observed, so both
are tried.

## Bitmap tags

Reference: spec chapter 8 "Bitmaps" (pp. 137-143). Impl:
`opensky/Formats/SWF/SWFBitmap.swift` (lossless) and `SWFBitmapJPEG.swift`
(JPEG family via ImageIO/CoreGraphics — Apple frameworks, no third-party
codec). All decoders produce `SWFBitmap`: RGBA8 row-major pixels, dimensions,
a `premultipliedAlpha` flag, and the detected source format.
`SWFBitmapDecoder.decode(tag:jpegTables:)` dispatches on the tag code.

DefineBitsLossless (20) / DefineBitsLossless2 (36): `CharacterID` UI16,
`BitmapFormat` UI8, width/height UI16, then one zlib stream. Formats: 3 =
8-bit colormapped (UI8 `BitmapColorTableSize` stores count minus one; RGB
table for tag 20, RGBA for tag 36; index rows padded to 32-bit boundaries),
4 = PIX15 (tag 20 only; 1 reserved + 5/5/5 bits MSB-first, rows padded), 5 =
PIX24 (tag 20: reserved byte + RGB) or 32-bit ARGB (tag 36). The expected
decompressed size is computed from format, dimensions, and row padding and
validated by `Zlib.decompress`. Per the spec (p. 143) the tag-36 ARGB pixel
data is already premultiplied by alpha and is passed through with
`premultipliedAlpha == true`. Open question: the spec states the premultiply
rule only for ARGB data, not for RGBA colormap entries — colormapped
Lossless2 output is flagged non-premultiplied here until observed otherwise.

JPEG family: JPEGTables (8) holds the movie-wide encoding tables for
DefineBits (6), whose body is only the scan — both streams carry SOI/EOI, so
the decodable image is tables-without-EOI + scan-without-SOI.
DefineBitsJPEG2 (21) is a self-contained image. DefineBitsJPEG3 (35) adds
`AlphaDataOffset` UI32 and a zlib-compressed one-byte-per-pixel alpha plane
after the image; DefineBitsJPEG4 (90) additionally inserts a `DeblockParam`
UI16 (8.8 fixed point; decoded, not applied). Pre-SWF8 payloads may carry an
erroneous `FF D9 FF D8` prefix, which is stripped. From SWF 8 the payload may
be PNG or GIF89a, detected by signature; the alpha plane applies to JPEG
payloads only (spec p. 139). JPEG color with a substituted alpha plane is
straight (non-premultiplied); PNG/GIF decode through a premultiplied
CoreGraphics context and are flagged accordingly.

## Display-list tags

Reference: spec chapter 3 "The display list" (pp. 31-39) plus DefineSprite in
chapter 13 (p. 233). Impl: `opensky/Formats/SWF/SWFDisplayList.swift` (tag
decode), `SWFMovie.swift` (dictionary + frame-1 list), `SWFScene.swift`
(flattening to draw commands), `SWFTransform.swift` / `SWFColorTransform.swift`
(the affine and color algebra).

A movie's visible content is a depth-keyed list of placed characters. Control
tags mutate that list; `ShowFrame` (1) publishes it. `SWFMovie.frame1` builds the
list up to the **first** `ShowFrame` and freezes it there, which is the static
render path; later define tags still enter the dictionary. Every later frame is
retained on `SWFTimeline` and stepped by the
[AS2 runtime](/engine/as2-runtime.md), which applies the same
place/modify/replace/remove semantics to a mutable tree.

| tag | name              | body                                                     |
| --- | ----------------- | -------------------------------------------------------- |
| 4   | PlaceObject       | `CharacterId` UI16, `Depth` UI16, MATRIX, optional CXFORM |
| 26  | PlaceObject2      | flag byte, `Depth` UI16, then the gated field run         |
| 70  | PlaceObject3      | two flag bytes, `Depth` UI16, class name, field run, extras |
| 5   | RemoveObject      | `CharacterId` UI16, `Depth` UI16                          |
| 28  | RemoveObject2     | `Depth` UI16                                              |
| 1   | ShowFrame         | empty                                                     |
| 9   | SetBackgroundColor| RGB record                                                |
| 39  | DefineSprite      | `SpriteID` UI16, `FrameCount` UI16, nested tag stream     |

PlaceObject2's flag byte, MSB to LSB: `HasClipActions`, `HasClipDepth`,
`HasName`, `HasRatio`, `HasColorTransform`, `HasMatrix`, `HasCharacter`,
`Move`. The gated fields follow in that (reverse) order: `CharacterId` UI16,
MATRIX, CXFORMWITHALPHA, `Ratio` UI16, `Name` STRING, `ClipDepth` UI16.
PlaceObject3 keeps that byte and adds a second one (MSB to LSB: reserved,
`OpaqueBackground`, `HasVisible`, `HasImage`, `HasClassName`,
`HasCacheAsBitmap`, `HasBlendMode`, `HasFilterList`); its class name precedes
the character id, and `SurfaceFilterList`, `BlendMode` UI8, `BitmapCache` UI8,
`Visible` UI8, and an RGBA `BackgroundColor` follow the clip depth.

Place semantics (spec p. 34), applied by `SWFDisplayListBuilder`:

* `Move` clear + character id -> place a new character at the depth.
* `Move` set, no character id -> modify the object already at the depth; the
  fields present overwrite, the rest persist. An empty depth here is a dangling
  placement: skipped and counted, never fatal.
* `Move` set + character id -> replace the character at the depth. The spec
  leaves the unspecified fields undefined; observed Flash/GFx behavior keeps the
  previous state, which is what OpenSky does.
* `RemoveObject`/`RemoveObject2` clear the depth (the character id in tag 5 is
  informational — removal is by depth).

MATRIX (spec p. 23) is bit-packed and byte-aligned: `HasScale` UB[1] (then
`NScaleBits` UB[5] and two SB 16.16 fixed-point terms), `HasRotate` UB[1] (same
shape), then `NTranslateBits` UB[5] and two SB translations in twips. Semantics:
`x' = x*ScaleX + y*RotateSkew1 + TranslateX`, `y' = x*RotateSkew0 + y*ScaleY +
TranslateY`. `SWFTransform` mirrors those field names so the concatenation
algebra stays checkable against the spec.

CXFORM / CXFORMWITHALPHA (spec pp. 24-25), also byte-aligned: `HasAddTerms`
UB[1], `HasMultTerms` UB[1], `Nbits` UB[4], then the multiply terms
(R, G, B[, A] as SB[Nbits], 8.8 fixed point — divide by 256) followed by the add
terms (same width, the -255..255 integer domain — divide by 255). Application is
`clamp(color * multiply + add, 0, 1)` in the straight-alpha domain; nesting
concatenates as `multiply = outer.multiply * inner.multiply`,
`add = outer.multiply * inner.add + outer.add`.

Clip layers: a placement carrying `ClipDepth` draws no color of its own and
masks every placement at depths `(depth, clipDepth]`. Ranges may interleave, so
`SWFScene` emits `beginClip`/`endClip` commands around the affected draws and
records how many masks are active per draw; the renderer turns that into a
counting stencil ([screen-space UI layer](/rendering/ui.md)).

DefineSprite (39) carries its own End-terminated tag stream in its body — the
same `RECORDHEADER` framing as the top level (`SWFFile.parseTags` is shared).
Each sprite keeps its own frame-1 display list, and the scene flattener expands
a placed sprite recursively, concatenating the parent transform and color
transform into every child (recursion bounded at 16 levels defensively; vanilla
nesting is shallow).

Parsed and deliberately not rendered, each counted so the deferral stays
measured: PlaceObject3 `SurfaceFilterList` (framed per the filter records in
spec chapter 3, pp. 42-47 — each `FilterID` selects a fixed body size, except
GradientGlow/GradientBevel whose size depends on `NumColors` and Convolution
whose size depends on the matrix dimensions) and `BlendMode`. `Ratio` is decoded
and retained; morph shapes are not implemented. `ClipActions` is no longer
skipped — see the next section.

Milestone 8.3.1 stopped discarding the frames after the first. Every timeline —
the main one and each sprite's — keeps an `SWFTimeline`: a `frames` array where
each `SWFTimelineFrame` holds its `steps` (`.place`/`.remove` in tag order) and
its `actions`. `SWFMovie.frame1` and `SWFSprite.frame1` are now computed from
`timeline.frame1`, which is still resolved from the tags up to and including the
first `ShowFrame`, so every display-list counter and every rendered frame is
unchanged. The later frames exist for the timeline runtime (8.3.x) and are not
executed today.

## Action tags — DoAction (12), DoInitAction (59)

Reference: spec chapter 5 "Actions" — "DoAction" and "ACTIONRECORD" (p. 63),
"DoInitAction" (p. 108), and the per-action field tables in the SWF 3 action
model (pp. 64-66), SWF 4 action model (pp. 68-88), SWF 5 action model
(pp. 89-107), SWF 6 action model (pp. 108-110), and SWF 7 action model
(pp. 111-116). Impl: `opensky/Formats/SWF/SWFActionParser.swift` (framing),
`SWFActionOperands.swift` (typed operands), `SWFAction.swift` (model types),
`SWFActionName.swift` (opcode table), `SWFTimeline.swift` (which frame a block
belongs to), `SWFMovieDecoder.swift` (tag routing).

Milestone 8.3.1 frames and names ActionScript 1/2 bytecode. **Nothing is
executed**; this is the inventory the 8.3.2 interpreter is built on.

| tag | name         | body                                                     |
| --- | ------------ | -------------------------------------------------------- |
| 12  | DoAction     | ACTIONRECORD stream, `ActionEndFlag` terminated          |
| 59  | DoInitAction | `Sprite ID` UI16, then the same stream                   |

DoAction's actions run when the enclosing frame's `ShowFrame` is reached,
wherever in the frame the tag sits, so OpenSky attaches each block to the frame
being accumulated (`SWFTimelineFrame.actions`). DoInitAction's actions run once,
before the named sprite is first instantiated; they are collected in tag order
into `SWFMovie.initActions` as `SWFDoInitAction(spriteId:actions:)`.

### ACTIONRECORD framing

| field      | type                 | notes                                     |
| ---------- | -------------------- | ----------------------------------------- |
| ActionCode | UI8                  | 0 is `ActionEndFlag` and ends the stream  |
| Length     | UI16 if code >= 0x80 | operand byte count, header excluded       |
| operands   | UI8[Length]          | absent when the code is below 0x80        |

Records are addressed by byte offset, because that is what `ActionJump` (0x99)
and `ActionIf` (0x9D) branch to and what an `ActionDefineFunction` body is sized
in. `SWFActionRecord` therefore carries `offset` (its own `ActionCode` byte) and
`endOffset` (one past the record); a `BranchOffset` of 0 points at `endOffset`.
`SWFActionBlock.record(atOffset:)` resolves a target by binary search over the
ascending offsets and returns nil for a branch into the middle of a record, and
`records(from:byteCount:)` returns the records of a nested body.

A missing trailing `ActionEndFlag` is not an error, and bytes after one are
ignored. Anything worse degrades instead of throwing, and is counted:

| warning                | cause                                                |
| ---------------------- | ---------------------------------------------------- |
| `truncatedRecord`      | header or operand payload past the end; stream stops |
| `malformedOperands`    | typed decode failed; raw bytes kept, framing resumes |
| `bodySizeOutOfBounds`  | `codeSize`/`Size`/Try sizes past the end; stream stops |
| `malformedClipActions` | CLIPACTIONS framing failed at this tag-body offset   |

### Opcode table

`SWFActionName` names all 100 codes the specification defines (99 actions plus
code 0). The spec prints code 0x08 as `ActionToggleQualty`; that is a
typographic error in the document and the table uses `ActionToggleQuality`.
Scaleform GFx executes the same bytecode — its extensions are host objects
reached through `ActionGetMember`/`ActionCallMethod`, not new opcodes — so an
unknown code means a malformed stream, not a GFx feature.

Seventeen opcodes get typed operands; the rest are framed with their bytes
retained and report `SWFActionOperands.none`.

| code | action                  | operands                                          |
| ---- | ----------------------- | ------------------------------------------------- |
| 0x81 | ActionGotoFrame         | `Frame` UI16                                      |
| 0x83 | ActionGetURL            | `UrlString` STRING, `TargetString` STRING         |
| 0x87 | ActionStoreRegister     | `RegisterNumber` UI8                              |
| 0x88 | ActionConstantPool      | `Count` UI16, `ConstantPool` STRING[Count]        |
| 0x8A | ActionWaitForFrame      | `Frame` UI16, `SkipCount` UI8                     |
| 0x8B | ActionSetTarget         | `TargetName` STRING                               |
| 0x8C | ActionGoToLabel         | `Label` STRING                                    |
| 0x8D | ActionWaitForFrame2     | `SkipCount` UI8                                   |
| 0x8E | ActionDefineFunction2   | see below                                         |
| 0x8F | ActionTry               | see below                                         |
| 0x94 | ActionWith              | `Size` UI16 (body length that follows)            |
| 0x96 | ActionPush              | repeated `Type` UI8 + value, filling the payload  |
| 0x99 | ActionJump              | `BranchOffset` SI16                               |
| 0x9A | ActionGetURL2           | `SendVarsMethod` UB[2], UB[4], target, variables  |
| 0x9B | ActionDefineFunction    | name, `NumParams` UI16, names, `codeSize` UI16    |
| 0x9D | ActionIf                | `BranchOffset` SI16                               |
| 0x9F | ActionGotoFrame2        | UB[6], `SceneBiasFlag`, `Play`, opt. `SceneBias`  |

`ActionPush` value types (spec p. 69); types 2 through 9 exist from SWF 5:

| type | value                                    |
| ---- | ---------------------------------------- |
| 0    | STRING (null-terminated)                 |
| 1    | FLOAT, 32-bit IEEE little-endian         |
| 2    | null                                     |
| 3    | undefined                                |
| 4    | register number UI8                      |
| 5    | Boolean UI8                              |
| 6    | DOUBLE, 64-bit IEEE (see the callout)    |
| 7    | 32-bit integer, read signed              |
| 8    | constant-pool index UI8                  |
| 9    | constant-pool index UI16                 |

**Observed vs. specified — the DOUBLE word order.** The spec calls the type-6
value a "64-bit IEEE double-precision little-endian double value", which reads
as a plain little-endian UI64. It is not: Flash authoring writes the two 32-bit
halves with the high-order word first. Measured over the vanilla Interface
movies (16,607 pushed doubles), the swapped reading yields ordinary constants —
`0.5`, `0.55`, `147.3`, `4294967295` — while the literal reading yields
denormals such as `1.06e-314` and magnitudes such as `-8.99e+307`.
`SWFActionOperandDecoder.readDouble` reassembles from two UI32 reads.

`ActionDefineFunction` (p. 92) is `FunctionName` STRING, `NumParams` UI16, that
many parameter-name STRINGs, then `codeSize` UI16. `ActionDefineFunction2`
(p. 111) inserts `RegisterCount` UI8 and a 16-bit preload/suppress flag word
after `NumParams`, and replaces the parameter names with REGISTERPARAM records
(`Register` UI8 + `ParamName` STRING). Both bodies are *not* nested inside the
record: the next `codeSize` bytes of the same stream are the body, which is why
`SWFActionBlock.records(from:byteCount:)` exists. `ActionWith` and `ActionTry`
size their bodies the same way; `ActionTry` (p. 115) is a flag byte (reserved
UB[5], `CatchInRegisterFlag`, `FinallyBlockFlag`, `CatchBlockFlag`), then
`TrySize`, `CatchSize`, and `FinallySize` UI16 — all three always present — then
`CatchName` STRING or `CatchRegister` UI8.

STRINGs decode UTF-8 with a CP1252 fallback, the same convention the display
list and edit-text parsers use.

## CLIPACTIONS

Reference: spec chapter 3 "The display list" — the CLIPACTIONS and
CLIPACTIONRECORD tables under "PlaceObject2" (pp. 36-37) and "ClipEventFlags"
(pp. 48-49). Impl: `opensky/Formats/SWF/SWFClipActions.swift`, attached to a
placement by `SWFDisplayList.swift`.

`PlaceFlagHasClipActions` (0x80 of the first flag byte) closes a PlaceObject2 or
PlaceObject3 body with the sprite's event handlers — `onPress`, `onEnterFrame`,
and the rest. Before 8.3.1 the parser recorded the flag and stopped reading; it
now frames the block and parses each handler's action stream into
`SWFPlacement.clipActions`.

| field             | type                             | notes                    |
| ----------------- | -------------------------------- | ------------------------ |
| Reserved          | UI16                             | must be 0                |
| AllEventFlags     | CLIPEVENTFLAGS                   | declared union of events |
| ClipActionRecords | CLIPACTIONRECORD[]               | one per handler          |
| ClipActionEndFlag | UI16 (SWF <= 5) or UI32 (SWF 6+) | all-zero terminator      |

Each CLIPACTIONRECORD is `EventFlags` CLIPEVENTFLAGS, `ActionRecordSize` UI32,
a `KeyCode` UI8 present only when `EventFlags` contains `ClipEventKeyPress`, and
then the ACTIONRECORD stream. `ActionRecordSize` is measured from the end of
that field to the next record, so the `KeyCode` byte counts against it: the
action stream is `ActionRecordSize - 1` bytes for a `keyPress` handler.

CLIPEVENTFLAGS is 2 bytes through SWF 5 and 4 bytes from SWF 6. The spec lists
it as a run of UB[1] fields; read as a little-endian word the bit values are
`ClipEventLoad` 0, `EnterFrame` 1, `Unload` 2, `MouseMove` 3, `MouseDown` 4,
`MouseUp` 5, `KeyDown` 6, `KeyUp` 7, `Data` 8, `Initialize` 9, `Press` 10,
`Release` 11, `ReleaseOutside` 12, `RollOver` 13, `RollOut` 14, `DragOver` 15,
`DragOut` 16, `KeyPress` 17, `Construct` 18. The narrow form is the low half of
the wide one, so `SWFClipEventFlags` stores one `UInt32` for both and the
movie's SWF version picks the read width. `AllEventFlags` is kept as written
rather than recomputed from the handlers, so a movie that disagrees with itself
stays inspectable.

Parsing never throws out of a place tag: a malformed CLIPACTIONS block yields
whatever handlers were framed plus a `malformedClipActions` warning, and the
placement is still applied. `SWFMovieTally.clipActions` still counts frame-1
placements carrying the flag, exactly as before (122 install-wide, unchanged).

## FrameLabel (43)

Reference: spec chapter 3 "The display list" — the "FrameLabel" control tag.
Impl: `opensky/Formats/SWF/SWFFrameLabel.swift`, attached to a frame by
`SWFTimeline.swift`.

| field       | type   | notes                                                  |
| ----------- | ------ | ------------------------------------------------------ |
| Name        | STRING | the label, null-terminated                             |
| NamedAnchor | UI8    | optional; present only when a byte remains in the body |

The named-anchor byte is optional in the sense that the tag length decides
whether it is there, which is how a SWF 5 and a SWF 6 movie both frame. A label
names the frame it appears in, so the decoder holds it until that frame's
`ShowFrame` closes and stores it on `SWFTimelineFrame.label`. Main timelines and
sprites both carry labels; `SWFTimeline.frameIndex(forLabel:)` resolves one,
matching exactly first and case-insensitively second, because ActionScript path
and label matching is case-insensitive below SWF 7 and authors mix casing.

Decoding this tag is what gives `gotoAndStop("label")` and `ActionGoToLabel`
(0x8C, 80 records in 4 movies) a target table. A malformed label costs the name,
never the frame.

## ExportAssets (56)

Reference: spec chapter 14 "Sharing fonts and other assets" — "ExportAssets",
the tag immediately preceding ImportAssets. Impl:
`opensky/Formats/SWF/SWFExportAssets.swift`.

Body: `Count` UI16, then `Count` pairs of `CharacterId` UI16 + `Name` STRING —
ImportAssets' body without the leading URL.

This is the **linkage table**, and it is what makes a registered class
instantiable. `Object.registerClass(linkageName, constructor)` binds a class to
a *name*, and only this tag says which character id that name belongs to;
without it a movie's own classes can never reach the display list.
`SWFMovie.exportedNames` holds name -> id and `SWFMovie.exportedIds` holds the
reverse (duplicate exports of one id keep the alphabetically first name, so the
map is deterministic). `MovieClip.attachMovie` looks up the same table.

A malformed export table costs the linkage and not the movie: the affected
classes simply never instantiate. That is deliberately laxer than
ImportAssets, whose failure loses a font the renderer needs.

## ImportAssets / ImportAssets2

Reference: spec chapter 14 "Sharing fonts and other assets" — ImportAssets (57,
p. 285) and ImportAssets2 (71, p. 286). Impl:
`opensky/Formats/SWF/SWFImportAssets.swift`.

Body: `URL` STRING, then (ImportAssets2 only) two reserved bytes (1 and 0),
`Count` UI16, and `Count` pairs of `CharacterId` UI16 + `Name` STRING. The
importing movie uses those character ids as if it had defined them; the actual
character lives in the named source movie.

This matters for text: vanilla Interface movies import their fonts from the
fontlib movies, so an edit text's `FontID` usually names a character the movie
never defines (523 of the 595 vanilla fields with content, before imports were
honored). `SWFMovie.importedNames` keeps the id -> export-name mapping and
`SWFMovieScene.resolvedFont(for:)` resolves that name through fontconfig, the
same path a zero-glyph placeholder font takes.

### Sprite imports — cross-movie character merge

Fonts were the only imports that resolved until M12.2.2. A **sprite** import
instantiated nothing, which is not a cosmetic loss: `inventorymenu.swf` places
`ItemCard_mc` (87), `InventoryLists_mc` (89) and `BottomBar_mc` (90) and defines
none of them, so the menu came up as 11 display nodes with no list at all.

`SWFMovieImportMerger` (`opensky/Formats/SWF/SWFMovieImportMerge.swift`, with the
id transform in `SWFCharacterRemap.swift`) resolves them. It is a pure transform
over `SWFMovie` values plus a resolver seam the loader supplies, so it is
testable with no filesystem, and `SWFMovieLoader.load(path:)` runs it before font
resolution so merged edit texts get substituted fonts too.

Per distinct import URL:

1. Resolve the URL against the *importing movie's own directory*, with `/`
   normalized to `\` and lowercased — `interface\inventorymenu.swf` plus
   `Inventory components/ItemCard.swf` is
   `interface\inventory components\itemcard.swf`.
2. Allocate `offset = (highest id in flight) + 1` and shift the source's **whole**
   id space by it, so no remap table is needed and no collision is possible.
3. Merge the remapped characters, `exportedNames`, `exportedIds`, `importedNames`
   and `DoInitAction` blocks. Init actions are prepended, deepest import first,
   so an imported CLIK class is registered before anything instantiates it.
4. Bind the placeholder id to the character the source exports under the imported
   name. The bound id also takes that linkage name in `exportedIds`, without
   which `SWFMovieRuntime.constructRegisteredClass` finds no class for the
   placement and no imported class ever constructs.

Every character-id reference is shifted, not just the dictionary keys:
`SWFShapeDefinition.characterId`, bitmap ids inside `SWFFillStyle.bitmap` for
both fill styles and `SWFLineStyle.fill`, `SWFBitmap.characterId`,
`SWFFontDefinition.fontID`, `SWFTextDefinition.characterId` and each
`SWFTextRecord.fontID`, `SWFEditText.characterId` and `.fontID`,
`SWFSprite.characterId`, `SWFPlacement.characterId` and `SWFRemoval.characterId`
in every frame of every timeline, the resolved `SWFTimeline.frame1` list, and
`SWFDoInitAction.spriteId`. A missed site is a silently wrong movie, which is why
the list is exhaustive rather than representative. `DefineScalingGrid` (78) is
not retained by the decoder, so it has nothing to remap.

Bounds and degradation, in the project's usual shape — counters, never a throw.
`SWFMovie.importDiagnostics` (`SWFImportMergeDiagnostics`) counts merged movies
and characters, bound and unresolved placeholders, missing sources, skipped
imports, depth-bound hits, cyclic imports and id-space overflows, and keeps up to
32 merged paths. Recursion is deduped by resolved path, cycle-guarded, and capped
at depth 4. A source whose shifted ids would leave `UInt16` is refused whole
rather than merged partially. An import whose asset ids are never placed and never
re-exported is skipped **without decoding the source**, which is what keeps
`gfxfontlib.swf` out of the merge.

Measured on `inventorymenu.swf`: 3 movies, 675 characters, 3 placeholders bound,
0 unresolved, 8 skipped, and 11 display nodes become 373 with 0 faults. See
[inventory menu](/engine/inventory-menu.md).

## Not implemented (yet)

* `ZWS` (LZMA) body decompression.
* Stroke tessellation for line styles (decoded, not meshed — see above).
* HTML/rich text layout in DefineEditText (raw markup retained, plain-text
  stripped). Runtime text — `field.text`, `SetText`, and the `VariableName`
  binding — is implemented by the [AS2 runtime](/engine/as2-runtime.md).
* `Ratio` morph shapes and button states. Frame stepping itself is implemented
  (the AS2 runtime steps a mutable display list); these two are not.
* PlaceObject3 filters and blend modes (framed, counted, not applied).
* Nothing further on CLIPACTIONS: the handlers are framed here and **dispatched**
  by the [AS2 runtime](/engine/as2-runtime.md) since milestone 8.3.2 phase 3.
  `construct` is the only clip event vanilla uses meaningfully (122 handlers in
  24 movies).
* DoABC (82) / ActionScript 3 and GFx extension tags.

## Verification

Unit tests: synthetic in-code fixtures (`openskyTests/SWFFileTests.swift`,
`openskyTests/SWFFixture.swift`) cover FWS field parsing, CWS round-trip, short
and long tags, End-tag termination with trailing bytes, unknown-tag passthrough,
the tag-name table, and rejection of bad signatures, `ZWS`, truncated headers,
truncated tag bodies, and a RECT running past the end.

Milestone 8.2.2 tests: `openskyTests/SWFShapeTests.swift` (styles, gradients,
bitmap fills, LINESTYLE2, extended counts, new-style flattening, glyph SHAPE,
malformed bodies) over the bit-exact `SWFShapeBodyBuilder` fixture
(`openskyTests/SWFShapeFixture.swift`), `SWFShapeTessellatorTests.swift`
(area-verified squares, holes, fill0/fill1 sides, shared interior edges,
winding vs. even-odd, deterministic curve flattening, cache), and
`SWFBitmapTests.swift` (all lossless formats with row padding, ARGB
premultiply, JPEG2/3/4, JPEGTables merge, PNG signature detection, erroneous
header stripping, typed failures) with ImageIO-generated synthetic payloads.

Milestone 8.2.3 tests: `openskyTests/SWFFontTests.swift` (DefineFont2/3 glyphs +
code tables, wide offsets/codes, layout with advances/bounds/kerning, the
companion tags, truncation) over `SWFFontBodyBuilder`;
`SWFTextTests.swift` (DefineText mixed style records, DefineText2 RGBA,
DefineEditText flag combinations, HTML strip, truncation) over
`SWFTextBodyBuilder` / `SWFEditTextBodyBuilder`; `SWFFontConfigTests.swift`
(directive/comment/unrecognized parsing, alias resolution by internal + export
name) with synthetic fontlib movies; and `SWFGlyphPathTests.swift` (y-flip,
DefineFont2 vs DefineFont3 scaling, conversion determinism, atlas caching).

Milestone 8.2.4 tests: `openskyTests/SWFDisplayListTests.swift` (CXFORM/
CXFORMWITHALPHA decode + algebra, all three PlaceObject versions with every
gated field, filters and blend modes, removals, background color, truncation,
and the `SWFTransform`/viewport math) over `openskyTests/SWFDisplayFixture.swift`
(bit-exact place/remove/sprite tag builders); `SWFMovieTests.swift` (dictionary
building, place/move/replace/remove, ShowFrame freeze, sprite frame 1, clip-depth
command ranges with interleaving, tallies); `SWFTextLayoutTests.swift` (record
state inheritance, kerning, wrap, alignment, missing glyphs); and
`SWFImportAssetsTests.swift` (both import tags, imported-font resolution).

Milestone 8.3.1 tests: `openskyTests/SWFActionTests.swift` (short and long record
framing with exact offsets, the opcode table, `ActionEndFlag` termination with
trailing bytes, a missing terminator, every `ActionPush` value type, the constant
pool, forward and backward branch offsets, offset seeking including a branch into
the middle of a record, `ActionDefineFunction`/`ActionDefineFunction2` body
framing, `ActionTry`, the remaining typed operands, unknown and undecoded opcodes
retained as raw bytes, and the three degradation paths — truncated payload,
nested body size past the end, malformed operands) and
`SWFActionMovieTests.swift` (DoAction landing on its frame, DoInitAction keyed by
sprite id, a sprite keeping its later frames and actions, CLIPACTIONS with
multiple handlers, a `keyPress` handler's `KeyCode`, the narrow SWF 5 flag word,
a malformed CLIPACTIONS block that keeps its placement, the action tally, and
frame 1 being untouched by any of it), over
`openskyTests/SWFActionFixture.swift`.

Milestone 8.3.2 tests: `openskyTests/SWFLinkageTests.swift` covers both tags
added here — FrameLabel with and without its named-anchor byte, labels attached
to the right frame on a main timeline and inside a sprite, exact-then-folded
label matching, ExportAssets records, the name -> id and id -> name maps
including the duplicate-id tie-break, and a truncated export table that loses
the linkage without losing the movie. The runtime that consumes them is tested
in `SWFMovieRuntimeTests`, `SWFRuntimePropertyTests`, and
`SWFRuntimeNativesTests` — see [AS2 runtime](/engine/as2-runtime.md).

`openskycli swf action-sweep` (milestone 8.3.1 stage 2) is the committed,
reproducible version of that inventory: `SWFActionInventory`
(`opensky/Formats/SWF/SWFActionInventory.swift`) walks every action block
`SWFMovie.actionBlocks` exposes plus every CLIPACTIONS handler, tallying opcode
frequency, unknown opcodes, a structurally-resolved host/GFx API name surface,
clip-event usage, and function/structure stats; `openskycli/SWFActionSweep.swift`
only parses `--movie`/`--limit` and prints. Per-movie numbers are also visible
in the app at `Developer > UI Lab > SWF movie`.

`openskycli swf sweep` ([CLI dev tool](/tools/cli.md)) is the milestone 8.2.1 +
8.2.2 + 8.2.3 + 8.2.4 gate: every archive/loose path under `interface\` ending
`.swf` parsed through `SWFFile` with a known/unknown tag-code tally, every shape
tag decoded and tessellated, every bitmap tag decoded to RGBA, every
DefineFont2/3 and DefineText/2/EditText tag decoded (glyphs also converted to
`CGPath`), every frame-1 display list assembled and flattened into draw commands
with its edit texts laid out, and a fontconfig alias-resolution report; any
shape/bitmap/font/text/display-list decode failure fails the sweep.
`openskycli swf render-sweep` is the GPU half: every movie is assigned to the
production renderer and its frame 1 rendered offscreen. `openskycli
swf action-sweep` is the AS2 inventory: see the results below and
[CLI dev tool](/tools/cli.md).

## Vanilla sweep results

`openskycli swf sweep` against the vanilla install (`Skyrim - Interface.bsa`):
53 `.swf` movies, all 53 parsed (0 `ZWS`/unsupported, 0 failed). 14,477 tags
total, all 14,477 known to the Adobe tag table — no unknown or GFx-extension
(~1000+) tag codes appeared in vanilla `Interface/*.swf`. Versions observed:
mostly SWF 15, with `racesex_menu.swf` at version 8 and `fonts_pl.swf` /
`fonts_ru.swf` / `gfxfontlib.swf` / `sharedcomponents.swf` at version 10.

Shapes and bitmaps (milestone 8.2.2): 2,677 shapes decoded and tessellated
with 0 failures — DefineShape 944, DefineShape2 1,097, DefineShape3 574,
DefineShape4 62 — producing 2,195,435 triangles. 453 bitmaps decoded with 0
failures: 451 DefineBitsLossless2 32-bit ARGB (`lossless32`) and 2 DefineBits
JPEG scans (`jpeg`) in `sharedcomponents.swf`, whose JPEGTables tag is empty
(0 bytes) — the scans are self-contained and decode without merged tables. No
colormapped/15-bit/24-bit lossless, DefineBitsJPEG2/3/4, PNG, or GIF payloads
appear in vanilla. Full per-file output: `logs/swf-shape-sweep.log`
(gitignored, not committed — AGENTS.md Legal & IP; reproduce with
`openskycli swf sweep`).

Fonts and text (milestone 8.2.3): 97 fonts decoded with 0 failures — 96 carry a
layout block; 54,988 glyphs total (54,987 code-mapped, 34,379 with a drawable
CGPath — the remainder are blank glyphs such as spaces), 17,336 kerning pairs.
One DefineFont3 in `hudmenu.swf` is a 0-glyph device-font placeholder. Text:
665 DefineEditText (644 with initial text, 571 HTML) and 0 DefineText/DefineText2
— vanilla Skyrim UI text is entirely dynamic (DefineEditText bound to variables),
so no static DefineText blocks appear. fontconfig: `Interface/fontconfig.txt`
declares 3 fontlibs (`fonts_console.swf`, `fonts_en.swf`, `fonts_cclub.swf`) and
20 `map` aliases, all 20 resolving against the fontlib movies; the `mapdefault`
and `validNameChars` directives are outside the implemented subset and reported
as unrecognized.

Display lists (milestone 8.2.4): 53 movies decoded with 0 failures, 130 frame-1
placements on the main timelines (5 movies place nothing at frame 1), 53
`SetBackgroundColor` tags. Place tags across the main timelines and every
sprite's frame 1: 0 PlaceObject, 5,926 PlaceObject2, 281 PlaceObject3, 3,202
`ShowFrame`, 3,971 sprites, 30 clip layers — and **0 moves and 0 removals**.
Vanilla frame 1 only places; the modify/replace/remove paths exist for
correctness and are exercised by unit tests, not by vanilla's first frame.
Flattening those lists yields 1,207 shape draws, 695 edit-text draws, 0
static-text draws (vanilla has no DefineText), and 22 clip ranges, with 20
placements referencing something undrawable. Recorded-but-deferred features:
233 filters, 25 blend modes, 122 `ClipActions` blocks; 0 dangling placements.

Text through the display list: all 595 edit texts that carry content resolve a
font and lay out 15,238 glyphs with 0 missing glyphs (100 further fields are
empty). That depends on ImportAssets2 — without it 523 of those fields resolve
nothing. One font name remains unresolved across the whole install.

An important consequence for acceptance: 1,032 of the 1,902 frame-1 draws
resolve to alpha 0 through their CXFORM. Vanilla menus hide most of their
content at frame 1 and reveal it from ActionScript, so a correct frame-1 render
of many movies is legitimately blank — 20 of the 53 movies change no pixels at
all, and 10 of them (the fontlib and asset-only movies) produce no draws
at all.

GPU frame-1 render (`openskycli swf render-sweep --size 960x600`): 53 movies,
53 rendered, 0 failed, 2,277 draws, 692,328 triangles, 44 stencil mask draws.
Per-movie highlights: `modmanager.swf` 275 draws / 372,128 changed pixels,
`creationclubmenu.swf` 97 draws with 164 glyphs / 344,207, `quest_journal.swf`
(rendered on its own) 612 draws with 1,535 glyphs / 237,525, `console.swf`
4 draws with 12 glyphs / 239,216, `hudmenu.swf` 185 draws with 24 mask draws /
7,637. Glyph
counts in a full 53-movie sweep under-report late movies because the shared
glyph atlas fills up (issue #127); `--movie <name>` renders one movie with a
fresh renderer for honest numbers. Full output: `logs/swf-render-sweep.log`,
optional frame captures under `logs/swf-frames/` — both gitignored, never
committed (AGENTS.md Legal & IP: a rendered vanilla movie embeds game art).

AS2 action inventory (`openskycli swf action-sweep`, milestone 8.3.1 stage 2):
53 movies, 0 failed, 3,414 action blocks (2,163 DoAction, 1,127 DoInitAction,
124 ClipActions), 533,562 ACTIONRECORDs, 56 distinct opcodes, **0 unknown
opcodes**. The five most-used opcodes are `ActionPush` (191,644), `ActionGetMember`
(83,487), `ActionPop` (37,127), `ActionSetMember` (30,757), and `ActionNot`
(28,569); every one of the 56 observed codes is in the Adobe action table.
1,323 `ActionDefineFunction` and 10,575 `ActionDefineFunction2` records appear
(max 23 registers used), 936 `ActionConstantPool` records (max pool size 404),
and zero `ActionWith`/`ActionTry` — vanilla menus never use the `with` block or
try/catch. The largest single action block is 32,240 bytes / 5,886 records.

The structurally-resolved host/GFx API surface (the name immediately preceding
`ActionGetMember`/`ActionSetMember`/`ActionCallMethod`/`ActionCallFunction`/
`ActionGetVariable`/`ActionSetVariable`/`ActionNewMethod`/`ActionDefineLocal`,
constant-pool references resolved) finds 3,382 distinct names. The ten most
common: `gfx` (8,094 occurrences across 41 movies), `_global` (3,526/42),
`Shared` (2,316/41), `prototype` (1,987/41), `ui` (1,935/41), `NavigationCode`
(1,669/34), `io` (1,596/38), `addProperty` (1,535/34), `GameDelegate`
(1,520/38), and `length` (1,513/41) — the `gfx.*` namespace (Scaleform's own
component library: `gfx.controls.Button`, `EventDispatcher`, `Constraints`,
and similar) dominates over game-specific names, confirming vanilla menus are
built on the stock GFx component framework rather than bespoke AS2.

CLIPACTIONS handler events: 124 handlers total, but only three carry a
non-`construct` event across the whole install — one `load` and one
`enterFrame` handler, both on `statsmenu.swf` — plus 122 `construct` handlers
(Scaleform's component-construction event, used by 24 movies). None of the
pointer/keyboard events (`press`, `release`, `rollOver`, `keyPress`, ...)
appear on a PlaceObject2/3 CLIPACTIONS block anywhere in vanilla — button-level
interactivity is driven by `ActionCallMethod`/`addEventListener` inside DoAction
bodies, not by clip-level event handlers. Ranked by action-record volume,
`quest_journal.swf` (33,692 records / 250 blocks) is the largest single AS2
consumer, followed by `modmanager.swf` (29,383/62) and `inventorymenu.swf`
(24,754/68); the reproduction command and full opcode/host-API tables are the
probe log, `logs/swf-action-sweep.log` (gitignored — AGENTS.md Legal & IP).

## Static-render acceptance (milestone 8.2.5)

The M8.2 acceptance renders frame 1 of selected vanilla menus, offscreen and
through the app's own path (`Developer > UI Lab`, see
[screen-space UI layer](/rendering/ui.md)), and compares each frame against a
movie-free baseline of the same scene. Numbers below are from
`openskycli swf render-sweep --movie '\<name>.swf'` (one movie per renderer, so
the shared glyph atlas is not already full) and an equivalent in-app run through
the picker; both agree exactly, which is the point of routing the CLI and the
app through the same `SWFMovieLoader` -> `Renderer.setSWFMovie(_:)` path.

Per movie at 960x600 (576,000 pixels), changed pixels against the baseline:

| Movie | Draws | Triangles | Glyphs | Mask draws | Changed px |
|---|---|---|---|---|---|
| `creationclubmenu.swf` | 97 | 11,030 | 164 | 0 | 344,207 |
| `console.swf` | 4 | 26 | 12 | 0 | 239,216 |
| `quest_journal.swf` | 612 | 88,294 | 1,535 | 2 | 237,525 |
| `bookmenu.swf` | 9 | 52 | 14 | 0 | 57,600 |
| `hudmenu.swf` | 185 | 18,088 | 124 | 24 | 7,637 |
| `book.swf` | 1 | 26 | 13 | 0 | 0 |
| `loadingmenu.swf` | 10 | 885 | 37 | 2 | 0 |

The same movies at 480x320 (153,600 pixels) scale as expected: 91,474 /
60,203 / 63,313 / 19,200 / 1,824 / 0 / 0. `hudmenu.swf` is the clip-stencil
demo — 12 clip layers become 24 stencil mask draws — and its small changed
count is correct: a HUD is mostly transparent. `book.swf` and `loadingmenu.swf`
encode draws but change nothing, the alpha-zero CXFORM case described above.

Movie-level tag tallies the UI Lab readout shows for the same set
(`PlaceObject`/`PlaceObject2`/`PlaceObject3`, then sprites / clip layers /
filters / blend modes / `ClipActions`): `console.swf` 0/7/0, 7 sprites;
`creationclubmenu.swf` 0/472/8, 272 sprites, 3 clips, 1 blend, 4 clip actions;
`quest_journal.swf` 0/627/28, 301 sprites, 1 clip, 27 filters, 36 clip actions;
`bookmenu.swf` 0/25/1, 30 sprites, 1 filter; `hudmenu.swf` 0/362/21, 291
sprites, 12 clips, 15 filters, 6 blends. Dangling placements are 0 everywhere.
`hudmenu.swf` is the one movie carrying the install's single unresolved font
name (`Times New Roman`), which the readout surfaces rather than hiding.

Whole-install accounting at 480x320 (`swf render-sweep`, all 53 movies in one
renderer): 53 rendered, 0 failed, 18 frames unchanged, 2,296 draws, 697,388
triangles, 6,033 glyphs, 44 mask draws, 1 unresolved font name. The 7,909
skipped items in that run are glyphs the shared atlas could not pack after it
filled up (issue #127), not decode failures — per-movie runs report 0 skipped
except `hudmenu.swf`, which skips 1.

What M8.3 (AS2 runtime subset) inherits: every menu whose frame 1 is blank is
blank because ActionScript has not run, not because decoding failed. The draws
are encoded and the geometry is correct; only the CXFORM alpha (and, for some
movies, a later frame) is missing. `book.swf` and `loadingmenu.swf` are the
clearest single-movie tests for that milestone. Milestone 8.3.1 closed the
reachability half of that gap: the bytecode, the later frames, and the event
handlers are all decoded and addressable now, so 8.3.2 only has to execute them.
