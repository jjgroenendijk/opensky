---
type: File Format
title: Grass records (GRAS)
description: Skyrim SE GRAS placement settings and the LTEX GNAM links to them.
tags: [format, plugin, records, grass, terrain]
---

# Grass records (GRAS)

A `GRAS` record is one grass model plus the rules for placing it on
[LAND texture layers](/formats/land.md). A land texture (`LTEX`) lists zero or more grasses
in repeated `GNAM` fields.

Layout source: xEdit dev-4.1.5
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.5/Core/wbDefinitionsTES5.pas)
(`wbGRAS`, with the water rule values and flags). Field meanings checked against the
Creation Kit wiki page [Grass](https://ck.uesp.net/wiki/Grass).

## GRAS

| Field | Size (bytes) | Meaning |
| --- | --- | --- |
| `EDID` | varies | Editor ID |
| `MODL` | varies | NIF path relative to `Data/` |
| `DATA` | 32 | Placement settings, below |

`DATA`:

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
OpenSky keeps any other value as unknown.

Flags: `0x01` vertex lighting, `0x02` uniform scaling, `0x04` fit to slope.

A `DATA` of any other size is an error. A record with no `DATA` or no `MODL` is kept, so a
cell can count it and skip it.

## LTEX GNAM

Each `GNAM` is one 4-byte `GRAS` FormID. The field repeats, and the order is kept. A `GNAM`
shorter than 4 bytes is an error, not a null reference.

Real data check on vanilla `Skyrim.esm`: 27 `GRAS` and 68 `LTEX` records decode. 20 `LTEX`
records have 39 `GNAM` links, and all of them resolve. Density is 3 to 79, position range 29
to 68, height range 0.2 to 0.4, and color range 0.05 to 0.3.
