---
type: File Format
title: Effect shader records
description: Skyrim SE EFSH effect shaders and the five DATA sizes.
tags: [format, plugin, magic, rendering]
---

# Effect shader records

`EFSH` gives a magic effect its look on an actor: a membrane, an edge glow, and particles.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `ICON` | zstring | Fill texture |
| `ICO2` | zstring | Particle texture |
| `NAM7` | zstring | Holes texture |
| `NAM8` | zstring | Membrane palette texture |
| `NAM9` | zstring | Particle palette texture |
| `DATA` | 308 to 400 bytes | The shader settings |

## DATA

`DATA` is a list of 100 members of 4 bytes each, in the order of xEdit's
`wbRecord(EFSH, ...)`. Older form versions stop early. The install has five sizes: 308,
312, 344, 396 and 400 bytes. OpenSky reads members until the bytes end and keeps the
size.

Most members are floats. These are not:

| Member | Storage |
| --- | --- |
| Legacy flags (first) | uint8 and 3 unused bytes |
| Blend modes, z-tests, animated-frame members | uint32 |
| Fill, edge, color-key and edge-width colors | RGBA bytes |
| Add-on models, ambient sound | FormID |
| Texture count U and V, flags | uint32 |
| Scene-graph emit depth limit (last) | uint16 and 2 unused bytes |

Flags: 0x01 no membrane shader, 0x08 no particle shader, 0x20 skin only, 0x8000 animated
particles, 0x01000000 blood geometry. A size that is not a multiple of 4 is tallied.
