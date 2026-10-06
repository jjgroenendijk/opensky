---
type: File Format
title: World records (WRLD, CELL, STAT, placeable objects, flora, workbenches)
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
`/MSTT`, `/TREE`, `/FLOR`, `/FURN`, `/ACTI`, `/TACT`, `/CONT`, and `/DOOR`
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

The decoder also reads `OBND`, the `MODT` and `MODS` that follow `MODL`, `DNAM` (maximum
angle, `MATO` material, and an SSE snow byte), and `MNAM` (four fixed 260-byte slots, each a
zstring LOD mesh path followed by leftover bytes). `Skyrim.esm`
has 9,720 STAT records; 9,712 have a model.

Record-header bit 23 (`0x00800000`) means `Is Marker` on `ACTI`, `DOOR`, `FURN`, and `STAT`
(xEdit lines 3306, 4912, 5210, and 10155). The game does not draw a marker, even when it
has a model, such as `XMarkerHeading` with `MarkerXHeading.nif`. In the five vanilla
masters, only these four types set the bit, and every base that sets it is a marker:
spawn points, idle and lean furniture, invisible chairs, map and door markers, and trailer
cameras. A flagged `FURN` is still usable furniture; only its mesh is hidden.

## MSTT, TREE, FLOR, FURN, ACTI, TACT, CONT, DOOR

These placeable base objects share the fields that matter here:

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `MODL` | zstring | model path |
| `RNAM` | lstring | ACTI and FLOR: activation text |
| `KSIZ` + `KWDA` | uint32 + FormID array | keywords |
| `KNAM` | FormID | ACTI and FURN: interaction keyword |
| `FNAM` | uint8 | DOOR flags; bit 1 means automatic |
| `MNAM` | uint32 | FURN marker flags; bit 25 turns off activation |
| `SNAM` | FormID | sound; meaning depends on the type (below) |
| `ANAM` | FormID | DOOR close sound |
| `BNAM` | FormID | DOOR loop sound |
| `VNAM` | FormID | ACTI activation sound; TACT voice type (`VTYP`) |
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

TACT uses `SNAM` as its loop sound, like ACTI.

A sound FormID can name an `SNDR`, or a legacy `SOUN` whose `SDSC` points to an `SNDR`. In
`Skyrim.esm`, all 497 of these links name an `SNDR` directly. Bases with each slot: DOOR
open 92, close 86, loop 0; ACTI activation 33, loop 18; CONT open 135, close 133.

## Flora, trees, and talking activators

xEdit lines (commit `9fb0168`): TACT 3243, TREE 10152, FLOR 10186.

FLOR and TREE carry what a harvest gives:

| field | type | meaning |
| --- | --- | --- |
| `PFIG` | FormID | the item a harvest gives: an `INGR`, `ALCH`, `MISC`, or `LVLI` |
| `SNAM` | FormID | harvest sound (`SNDR`) |
| `PFPC` | 4 x uint8 | percent chance in spring, summer, fall, and winter |

A FLOR reference offers the Harvest action, like a tree. A TACT reference offers Talk. Its use
key raises the talk event with the reference as speaker and the TACT `VNAM` voice type.
The dialogue runtime decides what happens next.

The five masters carry 108 FLOR and 30 TACT records, and all decode. Every TACT has a voice
type; for example `TG05TalkingRock01` names `VTYP` `0001B080`. Across FLOR and TREE, 178
produce links are set: 112 INGR, 34 MISC, 25 ALCH, and 7 LVLI. All of them resolve to a record
OpenSky decodes. `FloraSwampFungalPod01` gives `SwampFungalPod01`, and the tree stump
`TreePineForestStump02AMoraTapinella` gives `MoraTapinellaBits`.

## Workbench data

FURN `WBDT` is 2 bytes (xEdit FURN line 5129, `wbSkillEnum` line 3473):

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | uint8 | bench type |
| `0x01` | int8 | skill, as an actor-value index; -1 means none |

Bench types: 0 none, 1 create object, 2 smithing weapon, 3 enchanting, 4 enchanting
experiment, 5 alchemy, 6 alchemy experiment, 7 smithing armor. The skill range in xEdit is 6
(One-Handed) to 23 (Enchanting). An unknown bench type or skill keeps its raw value.

Which recipes a station offers comes from its keywords, not from the bench type. A recipe's
`BNAM` names a keyword ([recipes](/formats/recipes.md)), and the station carries it in
`KWDA`. A forge is a create-object bench with `CraftingSmithingForge`.

In the five masters, 47 FURN bases have a bench type other than none: 39 create object, 4
enchanting, 2 alchemy, 1 smithing weapon (`CraftingBlacksmithSharpeningWheel`, skill
Smithing), and 1 smithing armor (`CraftingBlacksmithArmorWorkbench`). The enchanting count
includes `DisenchantmentFont01` and `DLC2ApocryphaFountain`, which train no skill. Many
Hearthfire furnishings are create-object benches, each with its own
`BYOHBuildingInteriorPart...` keyword.

A field that is too short is counted as malformed, and the rest of the record still decodes.

## CELL extras

Source: xEdit `dev-4.1.6` (commit `9fb0168`), `wbRecord(CELL, ...)`.

| Field | Type | Meaning |
| --- | --- | --- |
| `XCIM` | FormID | `IMGS` image space |
| `XILL` | FormID | Lock list: a `FLST` or `NPC_` that may use the locks |
| `XCCM` | FormID | `REGN` whose sky and weather an interior shows |
| `XNAM` | zstring | Water noise texture |
| `XWEM` | zstring | Water environment map |
| `XWCN`, `XWCS` | uint32 | Water velocity count |
| `XWCU` | 16 bytes each | Water velocity: a vector and one unnamed float |
| `MHDT` | 1028 bytes | Max height data: a float offset, then 32 x 32 uint8 heights; kept raw |
| `TVDT` | bytes | Occlusion data, not named by xEdit; kept raw |
| `LNAM` | bytes | Leftover flags that now live in `XCLC` |

## WRLD extras

| Field | Type | Meaning |
| --- | --- | --- |
| `RNAM` | struct | Large references of one cell: int16 Y, int16 X, uint32 count, then per reference a `REFR` FormID, int16 Y, int16 X; repeated |
| `MHDT` | bytes | Max height data: min and max cell, then 4 uint8 heights per cell; kept raw |
| `WCTR` | 2 int16 | Fixed center cell |
| `LTMP` | FormID | Interior lighting `LGTM` |
| `XLCN` | FormID | `LCTN` |
| `NAM3`, `NAM4` | FormID, float | LOD water and its height |
| `ICON` | zstring | Map image |
| `MODL` | model group | Cloud model |
| `MNAM` | 28 bytes | Map: usable size (2 int32), NW cell and SE cell (2 int16 each), camera min height, max height, initial pitch |
| `ONAM` | 16 bytes | Map offset: scale, then X, Y, Z offset |
| `NAMA` | float | Distant LOD multiplier |
| `NAM0`, `NAM9` | 2 floats | Bounds min and max, in game units |
| `NNAM` | zstring | Canopy shadow, unused |
| `TNAM`, `UNAM` | zstring | HD LOD diffuse and normal textures |
| `OFST` | bytes | One uint32 offset per cell; kept raw |

A child worldspace that sets the `PNAM` "use map data" bit (0x04) shows its parent's map
data, not its own.

## Activator, door, furniture, flora, tree, and movable static details

Source: xEdit `dev-4.1.6` (commit `9fb0168`), `wbRecord(ACTI, ...)` and the records named below.

| Record | Field | Type | Meaning |
| --- | --- | --- | --- |
| all | `OBND` | 12 bytes | Object bounds |
| all | `MODL`, `MODT`, `MODS` | model group | See [records](/formats/records.md) |
| all | `DEST` group | destruction | See [records](/formats/records.md) |
| `ACTI`, `FURN`, `FLOR` | `PNAM` | 4 bytes | Marker color, RGBA |
| `TACT` | `PNAM` | 4 bytes | Unnamed by xEdit; read like the marker color |
| `ACTI`, `FURN`, `FLOR`, `TACT` | `FNAM` | uint16 | Flags |
| `ACTI` | `WNAM` | FormID | Water type `WATR` |
| `DOOR` | `TNAM` | FormID | Random teleport destination, a `CELL` or `WRLD`; repeated |
| `FURN` | `NAM1` | FormID | Associated spell |
| `FURN` | `ENAM`, `NAM0`, `FNMK` | uint32, 4 bytes, FormID | One marker: index, disabled entry points (2 unknown bytes, then uint16 flags), keyword |
| `FURN` | `FNPR` | 2 uint16 | Marker entry: type (0 none, 1 sit, 2 lay, 4 lean), entry point flags |
| `FURN` | `XMRK` | zstring | Marker model |
| `TREE` | `CNAM` | 12 floats | Trunk and branch flexibility, trunk, front, back, and side amplitude, front, back, and side frequency, leaf flexibility, amplitude, and frequency |
| `MSTT` | `DATA` | uint8 | Flags: 0x01 on local map, 0x02 unknown, 0x04 static |
| `MSTT` | `SNAM` | FormID | Looping sound |

Entry point flags: 0x01 front, 0x02 behind, 0x04 right, 0x08 left, 0x10 up.
