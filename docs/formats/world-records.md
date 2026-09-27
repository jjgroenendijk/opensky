---
type: File Format
title: World records (WRLD, CELL, STAT, placeable objects)
description: Layouts of worldspaces, cells, statics, and placeable base objects with their
  sounds.
tags: [format, plugin, records, worldspace, cell, reference]
---

# World records

These records build a cell: the worldspace, the cell, and the base objects placed in it. The
placed references are on [placed references](/formats/placed-references.md). Shared decode
rules are on [record decoders](/formats/records.md).
How a cell becomes a scene is on [cell scene](/engine/cell-scene.md).

Sources: UESP "Skyrim Mod:Mod File Format" pages `/WRLD`, `/CELL`, `/STAT`,
`/MSTT`, `/TREE`, `/FURN`, `/ACTI`, `/CONT`, and `/DOOR`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>), and xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/fd1e36020b2b5b6217e553dc0038983146a2e2dd/Core/wbDefinitionsTES5.pas).
Water fields are on [water](/formats/water.md) and lighting fields on
[lighting](/formats/lighting.md).

## WRLD

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID, for example `Tamriel` |
| `FULL` | lstring | name, for example `Skyrim` |
| `WNAM` | FormID | parent worldspace |
| `PNAM` | uint16 | what the parent passes down |
| `DATA` | uint8 | flags |
| `DNAM` | float32[2] | default land height and water height |
| `NAM2` | FormID | default water (`WATR`) |
| `XEZN` | FormID | default encounter zone (`ECZN`) |

`DATA` flags: `0x01` small world, `0x02` no fast travel, `0x08` no LOD water, `0x10` no
landscape, `0x20` no sky, `0x40` fixed dimensions, `0x80` no grass. Not read: `RNAM`,
`MNAM`, `NAM0`/`NAM9`, climate, and LOD fields. A world children group with the exterior
cells follows the record ([ESM](/formats/esm.md)).

`Skyrim.esm` has 37 worldspaces. Tamriel has 11,187 cells.

## CELL

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name (interior cells) |
| `DATA` | uint16 or uint8 | flags |
| `XCLC` | int32 x, int32 y, uint32 flags | grid position (exterior cells) |
| `XCLW` | float32 | water height |
| `XCWT` | FormID | water type (`WATR`) |
| `XCLL` | struct | lighting |
| `LTMP` | FormID | lighting template (`LGTM`) |
| `XCLR` | FormID array | regions (`REGN`) |
| `XCAS` | FormID | acoustic space (`ASPC`) |
| `XEZN` | FormID | encounter zone (`ECZN`) |
| `XLCN` | FormID | location (`LCTN`) |
| `XOWN` | FormID | owner, an NPC_ or FACT |
| `XRNK` | int32 | owner faction rank |

`DATA` flags: `0x01` interior, `0x02` has water, `0x08` no LOD water, `0x80` show sky; UESP
lists more. UESP notes that some records store one byte only.

`XCLC`: one cell is 4096 units wide. Some form-version-43 records have an 8-byte `XCLC`
without the flags word. The high bits of the flags hold Creation Kit noise.

`XOWN` and `XRNK` work as on a REFR ([placed references](/formats/placed-references.md)). A
reference in the cell without its own `XOWN` takes the cell's owner. That is why every crate in a
shop is owned ([crime](/engine/crime.md)). In the vanilla install, every owned Whiterun interior has
a 4-byte `XOWN` and none has `XRNK`.

Interior cells are in the CELL top group, in block groups (type 2) and sub-block groups
(type 3). xEdit `UpdateInteriorCellGroup` (in `wbImplementation.pas`) takes the low 24 bits
of the object ID in decimal: the block is the last digit and the sub-block is the digit
before it. For example, object ID 80074 is block 4, sub-block 7. OpenSky looks there first,
then in all other type-2 and type-3 groups, because the labels are only a hint. The FormID
and the `0x01` flag decide what the cell is.

## STAT

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `MODL` | zstring | mesh path under `Data/`; absent for a marker |

Not read: `MODT`, `DNAM` (maximum angle and material), `MNAM` (LOD models). `Skyrim.esm`
has 9,720 STAT records; 9,712 have a model.

## MSTT, TREE, FURN, ACTI, CONT, DOOR

These placeable base objects share the fields that matter here:

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `MODL` | zstring | model path |
| `RNAM` | lstring | ACTI only: activation text |
| `FNAM` | uint8 | DOOR flags; bit 1 means automatic |
| `MNAM` | uint32 | FURN marker flags; bit 25 turns off activation |
| `SNAM` | FormID | sound; meaning depends on the type (below) |
| `ANAM` | FormID | DOOR close sound |
| `BNAM` | FormID | DOOR loop sound |
| `VNAM` | FormID | ACTI activation sound |
| `QNAM` | FormID | CONT close sound (not `ANAM`, unlike DOOR) |
| `VMAD` | struct | scripts |

ACTI record-header bit 20 means `Ignore Object Interaction`. With it, the FURN bit 25, or
DOOR automatic, the player cannot use the object directly. xEdit lines: ACTI 3297-3332, CONT
4492-4521, DOOR 4908-4933, FURN 5205-5260, MSTT 5409-5437, TREE 10221-10253. CONT contents
are on [item records](/formats/item-records.md).

Sound fields by meaning:

| meaning | DOOR | ACTI | CONT |
| --- | --- | --- | --- |
| activation (once, on use) | `SNAM` | `VNAM` | `SNAM` |
| close (once) | `ANAM` | none | `QNAM` |
| loop (continuous) | `BNAM` | `SNAM` | none |

A sound FormID can name an `SNDR`, or a legacy `SOUN` whose `SDSC` points to an `SNDR`. In
`Skyrim.esm`, all 497 of these links name an `SNDR` directly. Bases with each slot: DOOR
open 92, close 86, loop 0; ACTI activation 33, loop 18; CONT open 135, close 133.
