---
type: File Format
title: Grass records (GRAS)
description: GRAS placement controls and the LTEX GNAM links that attach grass to terrain paint.
tags: [format, plugin, records, grass, terrain]
---

# Grass records (GRAS)

A `GRAS` record names one grass model and the rules for placing it on
[terrain texture layers](/formats/land.md). An `LTEX` (land texture) record lists zero or
more `GRAS` records in repeated `GNAM` fields.

Sources: xEdit `dev-4.1.5`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.5/Core/wbDefinitionsTES5.pas)
(`wbGRAS`, with the water-rule values and flags). Field meanings checked against the
Creation Kit page [Grass](https://ck.uesp.net/wiki/Grass).

## GRAS fields

| Field | Size | Meaning |
| --- | --- | --- |
| `EDID` | varies | Editor ID, optional |
| `MODL` | varies | NIF path under `Data/`, optional |
| `DATA` | 32 | Placement rules, below |

`DATA` layout:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint8 | Density, as a percent chance |
| 1 | uint8 | Minimum slope in degrees |
| 2 | uint8 | Maximum slope in degrees |
| 3 | uint8 | Unknown |
| 4 | uint16 | Distance from water, in game units |
| 6 | uint16 | Padding |
| 8 | uint32 | Water rule |
| 12 | float32 | Position range |
| 16 | float32 | Height range |
| 20 | float32 | Color range |
| 24 | float32 | Wave period |
| 28 | uint8 | Flags |
| 29 | 3 bytes | Padding |

Water rule values 0 to 7, in xEdit order: above at least, above at most, below at least,
below at most, either at least, either at most, either at most above, either at most below.
OpenSky keeps unknown values.

Flags: `0x01` vertex lighting, `0x02` uniform scaling, `0x04` fit to slope.

A `DATA` of any size other than 32 is an error. A record without `DATA` or `MODL` is kept,
so the cell code can count it and skip it.

## LTEX GNAM

Each `GNAM` is one 4-byte `GRAS` FormID. The field repeats, and OpenSky keeps the order. A
short `GNAM` is an error, not a null link.

## Vanilla values

In `Skyrim.esm` there are 27 `GRAS` and 68 `LTEX` records. 20 `LTEX` records carry 39 `GNAM`
links, and all of them resolve. Value ranges: density 3 to 79, position range 29 to 68,
height range 0.2 to 0.4, color range 0.05 to 0.3.
