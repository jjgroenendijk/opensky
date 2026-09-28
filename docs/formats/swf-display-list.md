---
type: File Format
title: SWF display list
description: PlaceObject and RemoveObject, MATRIX and CXFORM, clip layers, sprites and
  timelines, FrameLabel, ExportAssets, ImportAssets, and how imported sprites are merged.
tags: [format, swf, ui, scaleform, display-list]
---

# SWF display list

What a movie shows is a list of characters placed at depths. Control tags change the list.
`ShowFrame` (1) ends a frame. The container is on the [SWF](/formats/swf.md) page. Source: Adobe
SWF specification, version 19, chapter 3 "The display list" (pp. 31-49), DefineSprite in
chapter 13 (p. 233), and chapter 14 "Sharing fonts and other assets" (pp. 285-286).

## Tags

| Tag | Name | Body |
| --- | --- | --- |
| 4 | PlaceObject | `CharacterId` uint16, `Depth` uint16, MATRIX, optional CXFORM |
| 26 | PlaceObject2 | Flag byte, `Depth` uint16, then the fields the flags select |
| 70 | PlaceObject3 | Two flag bytes, `Depth` uint16, class name, fields, extras |
| 5 | RemoveObject | `CharacterId` uint16, `Depth` uint16 |
| 28 | RemoveObject2 | `Depth` uint16 |
| 1 | ShowFrame | Empty |
| 9 | SetBackgroundColor | RGB |
| 39 | DefineSprite | `SpriteID` uint16, `FrameCount` uint16, its own tag stream |

PlaceObject2 flags, from the high bit: `HasClipActions`, `HasClipDepth`, `HasName`, `HasRatio`,
`HasColorTransform`, `HasMatrix`, `HasCharacter`, `Move`. The fields come in the reverse order:
`CharacterId`, MATRIX, CXFORMWITHALPHA, `Ratio`, `Name`, `ClipDepth`, then clip actions (see
[SWF actions](/formats/swf-actions.md#clip-actions)).

PlaceObject3 keeps that byte and adds a second one. From the high bit: reserved,
`OpaqueBackground`, `HasVisible`, `HasImage`, `HasClassName`, `HasCacheAsBitmap`,
`HasBlendMode`, `HasFilterList`. The class name comes before the character ID. After the clip
depth come the filter list, `BlendMode`, `BitmapCache`, `Visible`, and an RGBA background color.

## Place rules

From p. 34:

- `Move` clear, with a character: place a new character at the depth.
- `Move` set, no character: change the object at the depth. The fields present replace the old
  ones. The rest stay. An empty depth here is skipped and counted.
- `Move` set, with a character: replace the character at the depth. The specification does not
  say what happens to the other fields. Flash and GFx keep the old ones, and so does OpenSky.
- RemoveObject and RemoveObject2 clear the depth. The character ID in tag 5 is only information.

In vanilla, frame 1 only places. It never moves or removes.

## MATRIX

MATRIX (p. 23) is a bit field, aligned to a byte. `HasScale` (1 bit), then `NScaleBits`
(5 bits) and two 16.16 fixed-point values. `HasRotate` (1 bit), with the same shape. Then
`NTranslateBits` (5 bits) and two translations in twips.

```text
x' = x * ScaleX      + y * RotateSkew1 + TranslateX
y' = x * RotateSkew0 + y * ScaleY      + TranslateY
```

## CXFORM

CXFORM and CXFORMWITHALPHA (pp. 24-25) are color transforms, also byte-aligned. `HasAddTerms`
(1 bit), `HasMultTerms` (1 bit), `Nbits` (4 bits). Then the multiply terms (R, G, B, and A with
alpha), in 8.8 fixed point, so divide by 256. Then the add terms, from -255 to 255, so divide by
255.

A color becomes `clamp(color * multiply + add, 0, 1)`, with straight (not premultiplied) alpha.
Nested transforms combine as:

```text
multiply = outer.multiply * inner.multiply
add      = outer.multiply * inner.add + outer.add
```

## Clip layers

A placement with `ClipDepth` draws no color. It is a mask for every placement at depths above
its own, up to and including `ClipDepth`. Masks can overlap. The renderer uses a counting
stencil for them ([SWF render layer](/rendering/swf-layer.md)).

## Sprites and timelines

DefineSprite holds its own tag stream, with the same record headers and its own End tag. A placed
sprite is drawn by drawing its children with the parent's transform and color transform joined
in. Nesting stops at 16 levels. Vanilla nesting is shallow.

Every timeline, the main one and each sprite's, keeps all its frames. Each frame holds its place
and remove steps in tag order, its actions, and its label. Frame 1 is the state at the first
`ShowFrame`. It is what a static drawing shows. The
[ActionScript runtime](/engine/as2-runtime.md) steps through the later frames.

## FrameLabel

FrameLabel (43): a `Name` string, then an optional `NamedAnchor` byte. The anchor byte is there
only when the tag has a byte left. A label names the frame it is in, so it is stored when that
frame's `ShowFrame` arrives.

A label lookup tries an exact match, then a match without regard to case. ActionScript names
ignore case below SWF 7, and authors mix cases. Labels are the targets of `gotoAndStop("label")`
and `ActionGoToLabel`. A bad label loses its name, not its frame.

## Exports

ExportAssets (56): `Count` uint16, then `Count` pairs of `CharacterId` uint16 and `Name` string.

This is the link table. `Object.registerClass(name, constructor)` ties a class to a name, and
only this tag says which character has that name. Without it, a movie's own classes can never
appear on the display list. `MovieClip.attachMovie` uses the same table. When one character is
exported under two names, OpenSky keeps the first name in alphabetical order.

A bad export table loses the links, not the movie.

## Imports

ImportAssets (57) and ImportAssets2 (71): `URL` string, then (ImportAssets2 only) two reserved
bytes, 1 and 0, then `Count` uint16 and `Count` pairs of `CharacterId` and `Name`. The movie uses
those IDs as if it had defined them. The real character is in the named source movie.

Fonts: vanilla menus import their fonts from the font library movies. Imported font names resolve
through `fontconfig.txt` (see [SWF fonts and text](/formats/swf-text.md#fontconfigtxt)).

Sprites: an imported sprite must be copied in from its source movie. Example:
`inventorymenu.swf` places `ItemCard_mc`, `InventoryLists_mc`, and `BottomBar_mc`, and defines
none of them. Without the merge, the menu has no item list.

For each import URL:

1. Resolve the URL against the importing movie's own folder, with `/` changed to `\` and all
   lowercase. Example: `interface\inventorymenu.swf` with `Inventory components/ItemCard.swf`
   gives `interface\inventory components\itemcard.swf`.
2. Add one offset to every ID in the source movie: the highest ID in use plus 1. So no IDs can
   collide, and no mapping table is needed.
3. Merge the characters, exports, imports, and DoInitAction blocks. Init actions from the deepest
   import run first, so an imported class exists before anything creates it.
4. Point the placeholder ID at the character the source exports under that name. The
   placeholder also gets that export name, or the class for it is never found.

Every place that holds a character ID must be shifted, not only the dictionary: shape IDs, bitmap
IDs inside fill styles and line styles, bitmaps, fonts, text and text records, edit texts,
sprites, every place and remove step in every frame, and DoInitAction sprite IDs. One missed
place gives a wrong movie with no error.

Limits: imports are followed by path at most once, loops are stopped, and depth stops at 4. A
source whose shifted IDs would not fit in uint16 is refused whole. An import whose IDs are never
placed or exported again is skipped without decoding the source. This keeps `gfxfontlib.swf` out.
Each case is counted. See [inventory menu](/engine/inventory-menu.md).
