---
type: File Format
title: SWF display list
description: PlaceObject 1-3, RemoveObject, MATRIX and CXFORM, clip layers, DefineSprite,
  FrameLabel, ExportAssets, ImportAssets, and how imported sprites merge.
tags: [format, swf, ui, scaleform]
---

# SWF display list

A movie shows a list of placed characters, sorted by depth. Control tags change the list,
and `ShowFrame` shows it. This page covers those tags and the tags that link movies. The
container is on [SWF](/formats/swf.md). The [AS2 runtime](/engine/as2-runtime.md) steps the
frames after the first.

References: Adobe SWF File Format Specification v19, chapter 3 "The display list"
(pp. 31-49), DefineSprite in chapter 13 (p. 233), and chapter 14 "Sharing fonts and other
assets" (pp. 285-286).

## Tags

| tag | name | body |
| --- | --- | --- |
| 4 | PlaceObject | `CharacterId` UI16, `Depth` UI16, MATRIX, optional CXFORM |
| 26 | PlaceObject2 | flag byte, `Depth` UI16, then the fields the flags select |
| 70 | PlaceObject3 | two flag bytes, `Depth` UI16, class name, fields, extras |
| 5 | RemoveObject | `CharacterId` UI16, `Depth` UI16 |
| 28 | RemoveObject2 | `Depth` UI16 |
| 1 | ShowFrame | empty |
| 9 | SetBackgroundColor | RGB |
| 39 | DefineSprite | `SpriteID` UI16, `FrameCount` UI16, its own tag stream |

PlaceObject2 flag byte, MSB to LSB: `HasClipActions`, `HasClipDepth`, `HasName`,
`HasRatio`, `HasColorTransform`, `HasMatrix`, `HasCharacter`, `Move`. The fields follow in
the reverse order: `CharacterId` UI16, MATRIX, CXFORMWITHALPHA, `Ratio` UI16, `Name`
STRING, `ClipDepth` UI16, then CLIPACTIONS ([SWF actions](/formats/swf-actions.md)).

PlaceObject3 adds a second flag byte, MSB to LSB: reserved, `OpaqueBackground`,
`HasVisible`, `HasImage`, `HasClassName`, `HasCacheAsBitmap`, `HasBlendMode`,
`HasFilterList`. The class name comes before the character ID. After the clip depth come
`SurfaceFilterList`, `BlendMode` UI8, `BitmapCache` UI8, `Visible` UI8, and an RGBA
`BackgroundColor`. Each filter's `FilterID` sets a fixed body size, except GradientGlow and
GradientBevel (size depends on `NumColors`) and Convolution (size depends on the matrix
size) (spec pp. 42-47).

## Place rules

From spec p. 34:

- `Move` clear and a character ID: place a new character at the depth.
- `Move` set and no character ID: change the object at the depth. Fields that are present
  replace old values; the others stay. If the depth is empty, OpenSky skips the tag.
- `Move` set and a character ID: replace the character at the depth. The spec does not say
  what happens to fields that are absent. Flash and GFx keep the old values, and OpenSky
  does the same.
- RemoveObject and RemoveObject2 clear the depth. The character ID in tag 5 is not used.

## MATRIX and CXFORM

MATRIX (spec p. 23) is bit-packed and byte-aligned: `HasScale` UB[1] (then `NScaleBits`
UB[5] and two 16.16 SB values), `HasRotate` UB[1] (same shape), then `NTranslateBits` UB[5]
and two SB translations in twips:

```text
x' = x * ScaleX + y * RotateSkew1 + TranslateX
y' = x * RotateSkew0 + y * ScaleY + TranslateY
```

CXFORM and CXFORMWITHALPHA (spec pp. 24-25) are also byte-aligned: `HasAddTerms` UB[1],
`HasMultTerms` UB[1], `Nbits` UB[4], then the multiply terms (R, G, B, and A for the alpha
form, as SB[Nbits], 8.8 fixed point, so divide by 256), then the add terms (same width,
-255 to 255, so divide by 255). The result is `clamp(color * multiply + add, 0, 1)` on
straight (not premultiplied) alpha. Nested transforms combine as:

```text
multiply = outer.multiply * inner.multiply
add      = outer.multiply * inner.add + outer.add
```

## Clip layers and sprites

A placement with `ClipDepth` draws no color. It masks every placement at depths
`(depth, clipDepth]`. Clip ranges can overlap, so the renderer uses a counting stencil.

A DefineSprite has its own timeline. A placed sprite draws its children with the parent's
transform and color transform applied. OpenSky stops at 16 levels of nesting; vanilla
nesting is shallow.

## FrameLabel (43)

| field | type | notes |
| --- | --- | --- |
| Name | STRING | the label |
| NamedAnchor | UI8 | only when a byte is left in the body |

The tag length decides whether the anchor byte is there. This is how both SWF 5 and SWF 6
movies frame the tag. A label names the frame it appears in. Label lookup tries an exact
match first, then ignores case, because ActionScript before SWF 7 ignores case and authors
mix it. Labels are the targets of `gotoAndStop("label")` and `ActionGoToLabel` (0x8C, used
80 times in 4 vanilla movies).

## ExportAssets (56)

The body is `Count` UI16, then `Count` pairs of `CharacterId` UI16 and `Name` STRING. It is
the ImportAssets body without the URL.

This is the linkage table. `Object.registerClass(linkageName, constructor)` binds a class to
a name, and only this tag says which character has that name. Without it, a movie's classes
can never be placed. `MovieClip.attachMovie` uses the same table. When one character is
exported under several names, OpenSky keeps the name that sorts first, so the result is
always the same.

## ImportAssets (57) and ImportAssets2 (71)

The body is `URL` STRING, then (ImportAssets2 only) two reserved bytes (1 and 0), `Count`
UI16, and `Count` pairs of `CharacterId` UI16 and `Name` STRING. The importing movie uses
those character IDs as if it defined them. The real character is in the source movie.

Vanilla movies import their fonts from the font library movies. So an edit text's `FontID`
usually names a character the movie does not define. OpenSky resolves the import name
through `fontconfig.txt` ([SWF text](/formats/swf-text.md)).

## Imported sprites

Movies also import sprites. For example, `inventorymenu.swf` places `ItemCard_mc` (87),
`InventoryLists_mc` (89), and `BottomBar_mc` (90) but defines none of them. Without the
imports the menu has 11 display nodes and no item list.

OpenSky merges the source movies into the importing movie. For each import URL:

1. Resolve the URL against the importing movie's folder, with `/` changed to `\` and all
   lowercase. `interface\inventorymenu.swf` plus `Inventory components/ItemCard.swf` gives
   `interface\inventory components\itemcard.swf`.
2. Shift every character ID in the source by `offset = (highest ID in use) + 1`. No two IDs
   can collide, and no lookup table is needed.
3. Merge the shifted characters, export names, import names, and DoInitAction blocks. Init
   actions go first, deepest import first, so an imported CLIK class is registered before
   anything creates it.
4. Point the placeholder ID at the character the source exports under the imported name.
   The placeholder also takes that linkage name, so the class constructor is found.

Every place that holds a character ID must shift: shapes, bitmap fills and line fills,
bitmaps, fonts, text records, edit texts, sprites, placements and removals in every frame,
and DoInitAction sprite IDs. One missed place gives a wrong movie with no error.

Limits: each source merges once, loops are stopped, and the depth limit is 4. A source whose
shifted IDs would not fit in UInt16 is not merged at all. An import whose characters are
never placed or exported again is skipped without reading the source. This keeps
`gfxfontlib.swf` out.

On `inventorymenu.swf`: 3 movies, 675 characters, 3 placeholders bound, 0 unresolved, 8
imports skipped. The 11 display nodes become 373. See
[inventory menu](/engine/inventory-menu.md).

## Vanilla display lists

On the main timelines and in each sprite's first frame: 0 PlaceObject, 5,926 PlaceObject2,
281 PlaceObject3, 3,202 `ShowFrame`, 3,971 sprites, 30 clip layers, 53
`SetBackgroundColor`. There are no moves and no removals in frame 1. The main timelines
place 130 characters at frame 1, and 5 movies place nothing. Frame 1 has 233 filters, 25
blend modes, and 122 CLIPACTIONS blocks.
