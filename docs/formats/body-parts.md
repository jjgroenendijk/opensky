---
type: File Format
title: Body part data
description: Skyrim SE BPTD body part data: hit, sever and explode parts of a skeleton.
tags: [format, plugin, actor]
---

# Body part data

`BPTD` names the parts of a creature that can be hit, cut off, or blown apart. A race links
it through `RACE GNAM`.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## Parts

After `EDID` and the model group, the record is a list of parts. A part starts at `BPTN`,
or at `BPNN` when the current part already has a node name. 49 records hold 111 parts on
the install.

| Field | Type | Meaning |
| --- | --- | --- |
| `BPTN` | lstring | Part name |
| `PNAM` | zstring | Pose-matching node |
| `BPNN` | zstring | Skeleton node the part sits on |
| `BPNT` | zstring | VATS target node |
| `BPNI` | zstring | IK start node |
| `BPND` | 84 bytes | Node data, below |
| `NAM1` | zstring | Limb-replacement model |
| `NAM4` | zstring | Gore target bone |
| `NAM5` | bytes | Texture hashes, kept raw |

## BPND

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | float | Damage multiplier |
| 4 | uint8 | Flags: 0x01 severable, 0x02 IK data, 0x04 IK biped data, 0x08 explodable, 0x10 IK is head, 0x20 IK head-tracking, 0x40 absolute to-hit chance |
| 5 | uint8 | Part type: 0 torso, 1 head, 2 eye, 3 look-at, 4 fly grab, 5 saddle |
| 6 | uint8 | Health percent |
| 7 | int8 | Actor value, -1 for none |
| 8 | uint8 | To-hit chance |
| 9 | uint8 | Explosion chance |
| 10 | uint16 | Explodable debris count |
| 12 | FormID | Explodable debris `DEBR` |
| 16 | FormID | Explodable explosion `EXPL` |
| 20 | float | Tracking max angle |
| 24 | float | Explodable debris scale |
| 28 | int32 | Severable debris count |
| 32 | FormID | Severable debris |
| 36 | FormID | Severable explosion |
| 40 | float | Severable debris scale |
| 44 | 3 floats | Gore offset |
| 56 | 3 floats | Gore rotation |
| 68 | FormID | Severable `IPDS` |
| 72 | FormID | Explodable `IPDS` |
| 76 | uint8 | Severable decal count |
| 77 | uint8 | Explodable decal count |
| 78 | 2 bytes | Not named by xEdit, kept |
| 80 | float | Limb-replacement scale |

Node names match a skeleton without regard to case.

## Skeleton nodes

A `BPTD` part names a skeleton node in `BPNN`. OpenSky checks each name against the
string table of a skeleton mesh, without case, as a hit or a miss. The skeleton is the
male `ANAM` of a race whose `GNAM` names the `BPTD`. A miss is reported, never a crash.

On the five masters 44 of the 45 `BPTD` records belong to a race. One node name misses:
`DwarvenBallistaCenturionBodyPartData` names `NPC_mainbody_bone`, which its skeleton
does not hold. Parts can also be listed by the `BPND` part type byte.
