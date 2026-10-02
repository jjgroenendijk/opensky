---
type: File Format
title: Combat style records
description: Skyrim SE CSTY combat styles and their float blocks that may stop early.
tags: [format, plugin, combat]
---

# Combat style records

`CSTY` holds the weights an actor's combat AI uses. An NPC links one through `NPC_ ZNAM`.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## Fields

Each block is a run of floats that may stop early; xEdit marks every member optional. The
install has `CSGD` at 8, 32 and 40 bytes, `CSME` at 28 and 32, `CSCR` at 8 and 16, and
`CSFL` at 4, 12 and 32. OpenSky keeps the floats present.

| Field | Members, in order |
| --- | --- |
| `CSGD` | Offensive, defensive, group offensive multipliers; equipment score multipliers for melee, magic, ranged, shout, unarmed, staff; avoid threat chance |
| `CSMD` | 8 bytes not named by xEdit, kept raw |
| `CSME` | Attack staggered, power attack staggered, power attack blocking, bash, bash recoil, bash attack, bash power attack, special attack multipliers |
| `CSCR` | Circle multiplier, fallback multiplier, flank distance, stalk time |
| `CSLR` | Strafe multiplier |
| `CSFL` | Hover chance, dive bomb chance, ground attack chance, hover time, ground attack time, perch attack chance, perch attack time, flying attack chance |
| `DATA` | uint32 flags: 0x01 dueling, 0x02 flanking, 0x04 allow dual wielding |

Header flag 0x80000 is an older allow-dual-wielding switch.

## Actors

An actor's combat style is its `NPC_` `ZNAM`. Through a template, it follows the "Use AI
Data" template flag (0x0010). xEdit ties `ZNAM` to no template flag. The Creation Kit
shows Combat Style on the AI Data tab of the actor window, so OpenSky uses that flag. This
choice is not confirmed against the running game.

In `Skyrim.esm`, 3,787 of the 5,118 `NPC_` records reach a combat style, directly or
through their templates.
