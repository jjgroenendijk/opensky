---
type: File Format
title: Camera records
description: Skyrim SE CAMS camera shots and CPTH camera paths.
tags: [format, plugin, camera]
---

# Camera records

Kill moves and VATS use scripted cameras. `CAMS` is one shot. `CPTH` is a path: a node in a
tree that holds shots and conditions.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## CAMS

| Field | Type | Meaning |
| --- | --- | --- |
| `MODL` | model group | Camera mesh |
| `DATA` | 40 or 44 bytes | See below |
| `MNAM` | FormID | `IMAD` |

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint32 | Action: 0 shoot, 1 fly, 2 hit, 3 zoom |
| 4 | uint32 | Location: 0 attacker, 1 projectile, 2 target, 3 lead actor |
| 8 | uint32 | Target, same values |
| 12 | uint32 | Flags: 0x01 position follows location, 0x02 rotation follows target, 0x04 do not follow bone, 0x08 first person, 0x10 no tracer, 0x20 start at time zero |
| 16 | 3 floats | Time multipliers: player, target, global |
| 28 | float | Max time |
| 32 | float | Min time |
| 36 | float | Target percent between actors |
| 40 | float | Near target distance (44 bytes only) |

xEdit marks the members from offset 8 on as optional. The install has 86 records of 40
bytes and 108 of 44.

## CPTH

| Field | Type | Meaning |
| --- | --- | --- |
| `CTDA` | conditions | When the path may run |
| `ANAM` | 2 FormIDs | Parent path and previous sibling |
| `DATA` | uint8 | Zoom: 0 default, 1 disable, 2 shot list; 0x80 set means shots are optional |
| `SNAM` | FormID | `CAMS`, repeated |

Like the idle tree, the parent links can form a cycle in modded data.

## The tree

OpenSky rebuilds the tree once, when the store is built:

1. Each node goes under its parent. A node whose parent is null, or names a record that is
   not in the store, is a root. The second kind is also counted as an orphan.
2. Siblings are ordered by following the previous-sibling links from the sibling whose
   link is null. A group with more than one such start, or with a loop, is counted as a
   broken chain and keeps file order for the nodes the chain does not reach.
3. A node that no root reaches sits on or below a parent cycle. It is counted as
   unreachable. No walk follows a link twice, so a cycle never hangs.

A `CPTH` `SNAM` shot that resolves to no `CAMS` is counted as dangling.

On the five masters 193 `CPTH` paths form 8 trees, at most 8 levels deep. Every
parent resolves, no chain is split, and every `SNAM` shot resolves to one of the 192
`CAMS` records.
