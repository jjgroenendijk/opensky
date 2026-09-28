---
type: File Format
title: World records
description: WRLD, CELL, REFR (teleport, ownership, linked references, primitive volumes), STAT,
  and the placeable base objects with their sound links.
tags: [format, esm, records, worldspace, cell, reference]
---

# World records (WRLD, CELL, REFR, STAT, base objects)

These records build a cell scene: the worldspace, its cells, the references placed in them, and
the base objects those references point at. The shared decode rules are on the
[record decoders](/formats/records.md) page. Water fields are on the [water](/formats/water.md)
page, and lighting fields on the [lighting](/formats/lighting.md) page.

Sources: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format) pages
`WRLD`, `CELL`, `REFR`, `STAT`, `MSTT`, `TREE`, `FURN`, `ACTI`, `CONT`, and `DOOR`; xEdit
`dev-4.1.6` `Core/wbDefinitionsTES5.pas` and `Core/wbImplementation.pas`.

## WRLD

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID, such as `Tamriel` |
| `FULL` | lstring | Name, such as "Skyrim" |
| `WNAM` | FormID | Parent worldspace |
| `PNAM` | uint16 | What the parent passes down |
| `DATA` | uint8 | Flags |
| `DNAM` | float32 x 2 | Default land and water heights |
| `NAM2` | FormID | Default water (`WATR`) |
| `CNAM` | FormID | Climate (see [weather](/formats/weather.md)) |
| `XEZN` | FormID | Default encounter zone |

Flags: `0x01` small world, `0x02` no fast travel, `0x08` no LOD water, `0x10` no landscape,
`0x20` no sky, `0x40` fixed size, `0x80` no grass. A world children group with the exterior
cells follows the record.

## CELL

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name, for interiors |
| `DATA` | uint8 or uint16 | Flags. Some records store one byte |
| `XCLC` | int32, int32, uint32 | Grid x, grid y, quad flags. Exteriors only |
| `XCLW` | float32 | Water height |
| `XCWT` | FormID | Water type |
| `XCLL` | struct | Lighting |
| `LTMP` | FormID | Lighting template |
| `XCLR` | FormID list | Regions |
| `XCAS` | FormID | Acoustic space |
| `XEZN` | FormID | Encounter zone |
| `XLCN` | FormID | Location |
| `XOWN` | FormID | Owner: `NPC_` or `FACT` |
| `XRNK` | int32 | Owner faction rank |

Flags: `0x01` interior, `0x02` has water, `0x08` no LOD water, `0x80` show sky. UESP lists more.

One exterior cell is 4096 units wide. Some form version 43 records have an 8-byte `XCLC` with no
quad flags. The high bits of the quad flags hold editor noise and are kept as they are.

A reference in the cell with no `XOWN` of its own takes the cell's owner. This is why every
crate in a shop is stolen when taken (see [crime](/engine/crime.md)). Owned Whiterun interiors
have `XOWN` and no `XRNK`. A zero owner means no owner.

## Finding an interior cell

Interior cells sit under the `CELL` top group, then a block group (type 2), then a sub-block
group (type 3). xEdit `UpdateInteriorCellGroup` names the groups from the last two decimal digits
of the object ID: block is the ones digit, sub-block the tens digit. Example: object ID 80074 is
block 4, sub-block 7. OpenSky looks in those groups first, then in all other block groups. The
group names are only a hint. The FormID and the interior flag decide identity.

## REFR

| Field | Type | Meaning |
| --- | --- | --- |
| `NAME` | FormID | The base object. Required |
| `DATA` | float32 x 6 | Position, then rotation in radians. Required |
| `XSCL` | float32 | Scale. Absent means 1 |
| `XTEL` | 32 bytes | Teleport target |
| `XRDS` | float32 | Light radius |
| `XEMI` | FormID | Light or region emittance |
| `XLKR` | 4 or 8 bytes, repeats | Linked reference |
| `XPRM` | 32 bytes | Primitive volume |
| `XOWN` | FormID | Owner: `NPC_` or `FACT` |
| `XRNK` | int32 | Faction rank needed to use it freely |
| `XCNT` | int32 | Stack size of a placed item. Absent means 1 |
| `VMAD` | varies | Script data (see [VMAD](/formats/vmad.md)) |

`XTEL` must be exactly 32 bytes: the target door `REFR`, a position (3 floats), a rotation in
radians (3 floats), and flags (`0x01` no alarm). Any other size is an error. Reading shifted
fields would send a door to the wrong place.

In Skyrim, `XOWN` is a plain 4-byte FormID. xEdit's `wbOwnership` makes it a 12-byte struct only
for Fallout 4 and later. `XOWN`, `XRNK`, and `XCNT` shorter than 4 bytes are dropped. Losing an
owner is better than losing the reference.

## Linked references (XLKR)

`XLKR` is the link `ObjectReference.GetLinkedRef(akKeyword)` follows. It repeats: one field per
link.

| Size | Layout |
| --- | --- |
| 8 bytes | Keyword (0 or `KYWD`), then the linked reference |
| 4 bytes | The linked reference only |

A zero keyword means no keyword, the same as the 4-byte form. A lookup with a keyword matches
only that keyword. A lookup with no keyword, the Papyrus default, matches only a link without
one.

A bad `XLKR` costs one link, not the reference. Below 4 bytes it is skipped. From 5 to 7 bytes
the first 4 are read.

The vanilla data fixes the field order. UESP says `Skyrim.esm` has 10 four-byte `XLKR` fields,
and that is what the file has. Every nonzero first FormID in an 8-byte field is a `KYWD`, and no
second FormID is. Most 8-byte fields have a zero keyword, so a link without a keyword is common.
No reference repeats a keyword.

xEdit's `wbStruct(XLKR, ...)` ends with `1`, `aOptionalFromElement`, which makes the second
FormID optional. xEdit also allows a reference in the first slot, because in the 4-byte form it
is the reference. `Skyrim.esm` never puts a reference in the first slot of an 8-byte field, so
OpenSky always reads it as a keyword.

## Primitive volumes (XPRM)

`XPRM` is the invisible volume of a trigger box, activation volume, portal box, or occlusion
volume. It does not repeat.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | float32 x 3 | Half size on each axis, before `XSCL` |
| 12 | float32 x 3 | Editor wireframe color, 0 to 1 |
| 24 | float32 | Unknown |
| 28 | uint32 | Type: 0 none, 1 box, 2 sphere, 3 portal box, 4 line |

UESP labels the first field "Bounds / 2", and xEdit reads it with a scale of 2. So it is a half
size. For a sphere it is a radius on each axis. A zero axis is allowed and appears in vanilla.

xEdit names the unknown float "Alpha" (`wbFloatRGBA`). UESP leaves it unnamed and lists the
values 0.15, 0.2, 0.25, and 1.0. Vanilla has exactly those four values, which confirms the field
order. OpenSky keeps the value and does not use it. UESP calls type 4 unknown, and xEdit calls
it "Line". It is not clear how a line uses three half sizes, so nothing should treat it as a box.

UESP writes "Color / 255", but every vanilla color is between 0 and 1. The division is only how
the Creation Kit shows it.

`XPRM` must be exactly 32 bytes, and the type must be 0 to 4. Anything else is an error for that
reference. A shifted read would give a trigger the wrong size, and guessing "box" would make a
volume of unknown shape. Vanilla has neither case.

## STAT

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `MODL` | zstring | Mesh path under `Data/`, such as `meshes\...`. Absent means a marker |

The path resolves through the [VFS](/formats/vfs.md). LOD models are on the
[LOD](/formats/lod.md) page.

## Placeable base objects

`MSTT` (moveable static), `TREE`, `FURN` (furniture), `ACTI` (activator), `CONT` (container),
and `DOOR` share one decoder.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `MODL` | zstring | Mesh path |
| `RNAM` | lstring | `ACTI` only: activation text |
| `FNAM` | uint8 | `DOOR` flags. Bit 1 means automatic |
| `MNAM` | uint32 | `FURN` marker flags. Bit 25 turns off activation |
| `SNAM`, `ANAM`, `BNAM`, `VNAM`, `QNAM` | FormID | Sounds, below |
| `VMAD` | varies | Script data |

`ACTI` record header bit 20 means "ignore object interaction". This bit, the `DOOR` automatic
flag, and the `FURN` bit 25 all mean the player cannot use the object by hand.

Sound fields mean different things per record:

| Use | DOOR | ACTI | CONT |
| --- | --- | --- | --- |
| Once, on use | `SNAM` | `VNAM` | `SNAM` |
| Once, on close | `ANAM` | - | `QNAM` |
| Loop | `BNAM` | `SNAM` | - |

Note that a container's close sound is `QNAM`, not `ANAM`. A sound link can name an `SNDR` or an
old `SOUN`, which points to an `SNDR` through `SDSC`. In vanilla, every one of these links names
an `SNDR` directly. See [world sound effects](/engine/world-sfx.md).
