---
type: File Format
title: Visual effect records
description: Skyrim SE ADDN addon nodes and RFCT visual effects.
tags: [format, plugin, rendering]
---

# Visual effect records

`ADDN` is a particle system that a mesh attaches by index, such as a torch flame. `RFCT`
pairs effect art with an effect shader for a spell or a weather.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## ADDN

| Field | Type | Meaning |
| --- | --- | --- |
| `OBND` | 12 bytes | Bounds |
| `MODL` | model group | The particle mesh |
| `DATA` | uint32 | Node index that a mesh's addon-node extra data names |
| `SNAM` | FormID | `SNDR` loop sound |
| `DNAM` | 4 bytes | uint16 master particle system cap, uint16 flags (1 master particle system, 3 always loaded) |

## RFCT

`DATA` is 12 bytes: an `ARTO` effect art, an `EFSH` shader, and uint32 flags (0x01 rotate
to face target, 0x02 attach to camera, 0x04 inherit rotation). A weather links an `RFCT`
through `WTHR NNAM`.
