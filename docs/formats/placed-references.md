---
type: File Format
title: Placed references (REFR, XLKR, XPRM)
description: REFR layout, teleport and ownership fields, linked references, and primitive
  volumes, with what Skyrim.esm contains.
tags: [format, plugin, records, reference, trigger]
---

# Placed references

A REFR places one base object in a cell. Placed actors (ACHR) have the same shape; see
[actor records](/formats/actors.md). The base objects are on
[world records](/formats/world-records.md). Shared decode rules are on
[record decoders](/formats/records.md).

Sources: UESP [`/REFR`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REFR) and xEdit
`dev-4.1.6` `Core/wbDefinitionsTES5.pas`.

## REFR fields

| field | type | meaning |
| --- | --- | --- |
| `NAME` | FormID | base object; required |
| `DATA` | float32[6] | position, then rotation in radians; required |
| `XSCL` | float32 | scale; absent means 1.0 |
| `XTEL` | 32 bytes | teleport destination |
| `XRDS` | float32 | light radius |
| `XEMI` | FormID | emittance (`LIGH` or `REGN`) |
| `XLKR` | 4 or 8 bytes | linked reference; repeated |
| `XPRM` | 32 bytes | primitive volume |
| `XOWN` | FormID | owner, an NPC_ or FACT |
| `XRNK` | int32 | faction rank needed to use it freely |
| `XCNT` | int32 | stack size of a placed item; absent means 1 |
| `VMAD` | struct | scripts ([VMAD](/formats/vmad.md)) |

`XTEL` is always 32 bytes: destination door REFR FormID, position float32[3], rotation
float32[3] in radians, and uint32 flags (`0x01` no alarm). Any other size is malformed.

`XOWN` is a 4-byte FormID in Skyrim. xEdit's
[`wbOwnership`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)
uses a 12-byte form only from Fallout 4 on. A null `XOWN` means not owned. `XRNK` matters
only when the owner is a faction. In `Skyrim.esm`, 7,765 references have `XOWN` and 118 have
`XCNT`.

## XLKR: linked references

`XLKR` is the link that Papyrus `ObjectReference.GetLinkedRef(akKeyword)` follows. It
repeats: one field per link.

| bytes | layout |
| --- | --- |
| 8 | FormID keyword (0 or `KYWD`), FormID linked reference |
| 4 | FormID linked reference, no keyword |

A null keyword means the same as the 4-byte form. `GetLinkedRef` with a keyword matches only
that keyword; without one it matches only a link with no keyword.

UESP's REFR page says: "8-byte struct: formid 0 or KYWD ..., formid REFR ...; 10 instances
of 4 byte struct with just a formid in Skyrim.esm". xEdit line 9910 declares
`wbRArray('Linked References', wbStruct(XLKR, 'Linked Reference', [wbFormIDCk('Keyword/Ref',
...), wbFormIDCk('Ref', ...)], cpNormal, False, nil, 1))`. The last `1` is
`aOptionalFromElement` (`Core/wbInterface.pas` line 4345), which makes the second FormID
optional and the 4-byte form valid.

In `Skyrim.esm`: 12,477 `XLKR` on 11,287 of 693,333 REFRs. 12,467 are 8 bytes and 10 are 4
bytes, as UESP says. 10,244 of the 8-byte ones have a null keyword. All 56 different
keywords are `KYWD` records, and the second FormID is never a keyword, which confirms the
order. No reference repeats a keyword or has two links without one. The most links on one
reference is 19.

Uncertain: xEdit allows `PLYR`, `ACHR`, or `REFR` in the first slot, because in the 4-byte
form that slot is the reference. `Skyrim.esm` never puts a reference in the first slot of an
8-byte form, so OpenSky reads it as a keyword.

## XPRM: primitive volume

`XPRM` is an invisible volume: trigger boxes, activation volumes, portal boxes, and
occlusion volumes. A reference has at most one.

| offset | type | meaning |
| --- | --- | --- |
| 0 | float32[3] | half size on each axis, before `XSCL` |
| 12 | float32[3] | Creation Kit wireframe color, 0 to 1 |
| 24 | float32 | unknown; xEdit calls it "Alpha" |
| 28 | uint32 | shape: 0 none, 1 box, 2 sphere, 3 portal box, 4 line |

The size is half the size: UESP says "Bounds / 2" and xEdit shows it with a scale of 2. For a
sphere, the three values are radii. Any size other than 32 bytes, or a shape above 4, is
malformed, because a guessed volume would have the wrong size or shape.

UESP's REFR page says: "32 byte struct: float[3] - x,y,z Bounds / 2; float[3] - r,g,b Color
/ 255; float - unknown: 0.15, 0.2, 0.25, 1.0 seen, same for any given base object; uint32 -
unknown: 1-4 seen, 1 Box, 2 Sphere, 3 Portal Box, 4 Unknown". xEdit line 9701 declares
`wbStruct(XPRM, 'Primitive', [wbStruct('Bounds', [wbFloat('X', cpNormal, True, 2, 4), ...]),
wbFloatRGBA, wbInteger('Type', itU32, wbEnum(['None', 'Box', 'Sphere', 'Portal Box',
'Line']))])`. `wbFloatRGBA` is red, green, blue, alpha (`Core/wbDefinitionsCommon.pas`
line 6484).

In `Skyrim.esm`: 13,668 `XPRM` on 13,668 REFRs, all 32 bytes. Shapes: box 10,163, sphere
137, portal box 3,135, line 233, and never 0. 129 axes are exactly zero, and the largest
half size is 18,027.004. Every color value is in 0 to 1, so UESP's "Color / 255" is only how
the Creation Kit shows it. The unknown float has exactly four values, 0.15, 0.2, 0.25, and
1.0, as UESP says. This confirms the field order.

Uncertain: the four values of the unknown float look like an editor drawing hint, not
something the game uses. How a line volume uses three sizes is also not known.
