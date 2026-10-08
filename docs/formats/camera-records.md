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
| `DATA` | uint8 | Zoom: 0 default, 1 disable, 2 shot list; 0x80 set means shots are optional (xEdit names; see below) |
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

## Shot selection

No open source describes how the game walks the tree, so the walk is OpenSky's reading of the
data. For one attacker and one target:

1. The roots are tried in sibling order. The first root that yields shots wins.
2. A path's conditions run on the attacker, with the target as the Target run-on. A failed
   path rejects everything below it.
3. A passing path hands over to its first child that yields shots. It offers its own shots
   only when no child does. A passing path with no shots anywhere below it yields nothing,
   and the walk goes on to its next sibling.
4. The chosen path's shots are grouped by `CAMS` action: shoot, then fly, then hit, then
   zoom. One shot is picked at random from each group, and the picks play in that order. A
   shot without `DATA` plays in the first group.

The tree shows why the groups are stages. A bow path such as
`PlayerActionShot01RBasic02COPY0000` holds a shoot shot and a fly shot side by side, plus
slower variants of each (`FC03aPlayerActionCam01R`, `FC03aSPlayerActionCam01R`). A random pick
from the flat list would fly before the arrow left the bow.

### The zoom byte

xEdit names `DATA` value 1 "disable". OpenSky does not skip such a path. On the masters the
two big roots, `PlayerDeath` and `DoVatsAtAll`, both have zoom 1, and every kill-move path sits
under one of them. Reading 1 as "disable" would turn off every kill cam. The meaning of the
byte is not known; OpenSky reads it and ignores it.

### Condition functions

Most path conditions use VATS functions. xEdit names them in its condition function table
(`wbDefinitionsTES5.pas`, `dev-4.1.6`). No source documents what they return, so OpenSky
reads it from the comparisons the vanilla paths make:

| Index | Creation Kit number | Function | Vanilla use | OpenSky returns |
| --- | --- | --- | --- | --- |
| 407 | 4503 | `GetVATSValue` member 4 | `>= 768`, `>= 256` | Units from attacker to target |
| 407 | 4503 | `GetVATSValue` other members | `== 1` or `== 0` | 1 when the member equals parameter 2 |
| 515 to 518 | 4611 to 4614 | `GetVATSRightAreaFree`, `Left`, `Back`, `Front` | `>= 150`, `>= 256`, `>= 64` | Units of free room on that side |
| 522, 523 | 4618, 4619 | `GetVATSRightTargetVisible`, `Left` | `== 1` | 1 when that side has 150 units of room |

`GetVATSValue` members 0 weapon, 2 target base, 6 action, 15 weapon type, 18 projectile type,
19 delivery, and 20 casting type are equality tests. For example, `MagicOrBowCams` asks for
action 3 or action 4, and `RangedKills` asks that the projectile type is not 2 (beam) and the
casting type is not 2 (concentration). Member 4 is compared with distances, so it is a
distance.

For a kill, the coordinator fills these facts:

- Action: 4 (ranged) with a bow or crossbow, else 1 (one-hand melee). Projectile type 6
  (arrow) with a bow or crossbow.
- Weapon and weapon type: the first weapon the player has equipped.
- The room on a side is how far the camera collision probe moves from the attacker's chest
  in that direction, up to 512 units.
- A few conditions run on the target, such as the left-side room of `F12BulletTime03Near`.
  OpenSky measures room around the attacker only.

With these facts, a bow kill on the real install picks `PlayerActionShot01RBasic02` and plays
its shoot, fly, and hit stages. The `World > Kill Cam` panel lists the first failing function
of each path.

The other functions the vanilla paths use, named by the same xEdit table. The Creation Kit
number is the index plus 4096:

| Index | Creation Kit number | Function | Vanilla use | OpenSky |
| --- | --- | --- | --- | --- |
| 36 | 4132 | `MenuMode` | `ShowAttacker`, `== 1` | Not supported. The condition context holds no menu state. `ShowAttacker` also needs `GetRandomPercent < 0`, which is never true |
| 69 | 4165 | `GetIsRace` | Run on the target, `!= 1` for each large race | Evaluated from the target's race |
| 313 | 4409 | `GetPairedAnimation` | `PairedKillTest`, `== 1` | Evaluated, always 0: OpenSky plays no paired animation |
| 391 | 4487 | `IsPC1stPerson` | `1stPRandom`, `1stPFailsafeCam`, `== 1` | Evaluated from the player's camera mode |
| 594 | 4690 | `GetIsFlying` | `ExitDontShootFlyingDragons`, `== 1` | Evaluated, always 0: no actor flies yet |
| 675 | 4771 | `GetGraphVariableInt` | `bShortKillMove`, `Is3rdPKillOnly` on the attacker | Not supported. The condition context does not read behavior graph variables. Every use sits under `PairedKillTest` |

So a melee kill still ends at `ExitWeRanOutOfCams`. The melee paths sit under
`PairedKillTest`, and its `GetPairedAnimation` is 1 only during a paired kill move. Melee kill
cams play once kill moves exist: that work sets the paired animation flag of the actor state,
and adds `GetGraphVariableInt` for the kill-move variables.
