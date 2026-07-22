---
type: File Format
title: Grass records (GRAS)
description: Skyrim SE GRAS placement controls and LTEX GNAM links decoded by OpenSky.
tags: [format, plugin, records, grass, terrain]
timestamp: 2026-07-22T00:00:00Z
---

# Grass records, Skyrim SE

GRAS defines one procedural vegetation model plus controls used when placing it
on [LAND texture layers](/formats/land.md). LTEX connects terrain paint to zero
or more GRAS records through repeated GNAM fields.

Primary layout source: xEdit dev-4.1.5
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.5/Core/wbDefinitionsTES5.pas)
(`wbGRAS`, including water-rule enum and flags). Field meanings cross-checked
against Creation Kit [Grass](https://ck.uesp.net/wiki/Grass). Impl:
`opensky/Formats/ESM/Records/Grass.swift` and
`opensky/Formats/ESM/Records/LandTexture.swift`.

## GRAS -> Grass

| field | size (B) | decoded |
| ----- | -------- | ------- |
| EDID | variable | optional editor ID zstring |
| MODL | variable | optional NIF path relative to `Data/` |
| DATA | 32 | fixed placement-control body below |

DATA layout:

| offset | type | meaning |
| ------ | ---- | ------- |
| 0 | uint8 | density, interpreted as percent chance |
| 1 | uint8 | minimum slope in degrees |
| 2 | uint8 | maximum slope in degrees |
| 3 | uint8 | unknown, skipped |
| 4 | uint16 | distance in game units from water |
| 6 | uint16 | padding |
| 8 | uint32 | water-distance rule enum |
| 12 | float32 | position range |
| 16 | float32 | height range |
| 20 | float32 | color range |
| 24 | float32 | wave period |
| 28 | uint8 | flags |
| 29 | 3 bytes | padding |

Water-rule raw values 0-7 map, in xEdit order, to above-at-least,
above-at-most, below-at-least, below-at-most, either-at-least,
either-at-most, either-at-most-above, and either-at-most-below. Unknown values
remain representable as `WaterRule.unknown(rawValue)`.

Flag bits:

- `0x01`: vertex lighting
- `0x02`: uniform scaling
- `0x04`: fit to slope

DATA with any size other than 32 throws `ESMError.malformed`. Missing DATA or
MODL stays representable as nil -> cell integration can count + skip an
unusable mod record without losing identity. Unknown fields and unknown flag
bits survive decode policy without blocking known controls.

## LTEX GNAM

Each 4-byte GNAM is one GRAS FormID. Fields repeat; `LandTexture.grasses`
preserves record order. Truncated GNAM throws through `BinaryReader`; it is not
silently treated as a null reference.

## Verification

Synthetic fixtures cover every DATA member, known + unknown water rules,
unknown flag retention, missing DATA, wrong record type, wrong DATA size,
repeated GNAM, and truncated GNAM.

Env-gated `GrassRealDataTests` sweep on vanilla Skyrim.esm, 2026-07-22:

- 27 GRAS + 68 LTEX decoded, no throws.
- 39 GNAM links across 20 LTEX records; 0 unresolved.
- density range 3-79; position range 29-68.
- height range 0.2-0.4; color range 0.05-0.3.

Game bytes remain read-only external input. Probe summary lives only in
gitignored `logs/grass-sweep.log`.
