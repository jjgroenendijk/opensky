---
type: File Format
title: Scene records
description: Skyrim SE SCEN fields: phases, actors, actions, and their ordered field runs.
tags: [format, plugin, dialogue, quest]
---

# Scene records

A scene is a quest-owned script of phases, actors, and actions, such as a guard talk or a
cart ride. `SCEN` stores it as one flat field list. The order of the fields gives the
structure, so the decoder walks them with a small state machine.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## Top-level fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `VMAD` | script data | Scripts and fragments, see [VMAD](/formats/vmad.md) |
| `FNAM` | uint32 | Flags |
| `PNAM` | FormID | Owner `QUST` |
| `INAM` | uint32 | Last action index |
| `VNAM` | 16 bytes | Actor behavior: death, combat, dialogue, observe combat (4 uint32) |
| `CTDA` | condition | Scene conditions, see [conditions](/formats/conditions.md) |

## Runs

| Opener | Closer | Content |
| --- | --- | --- |
| `HNAM` (empty) | `HNAM` (empty) | A phase: `NAM0` name, start conditions, `NEXT`, completion conditions, `NEXT`, `WNAM` editor width |
| `ALID` (int32 alias) | the next field that is not `LNAM` or `DNAM` | An actor: `LNAM` flags, `DNAM` behavior flags |
| `ANAM` (2 bytes, uint16 type) | `ANAM` (empty) | An action |

Inside an action: `NAM0` name, `ALID` alias, `LNAM` unnamed bytes, `INAM` index, `FNAM`
flags, `SNAM` start phase, `ENAM` end phase. The type picks the rest:

| Type | Meaning | Fields |
| --- | --- | --- |
| 0 | Dialogue | `DATA` topic, `HTID` head-track alias, `DMAX`, `DMIN` looping range, `DEMO` emotion type, `DEVA` emotion value |
| 1 | Package | `PNAM` packages, repeated |
| 2 | Timer | A second `SNAM`, a float duration |

The first `SNAM` in an action is always the start phase. A run still open at the end of the
record is tallied as a mismatch.

## Legacy fields

354 records carry `SCHR`, `QNAM`, `SCTX`, `SCDA`, and `SCRO` fields from an older script
format. xEdit marks them unused. The decoder reads past them and keeps nothing.

## Lookup

The scene store lists the scenes of each quest through `PNAM`. A dialogue action resolves
to its `DIAL` through `DATA`, and a scene actor joins the quest alias with the same alias
ID. A scene actor whose alias the quest lacks keeps a nil alias.

On the five masters the 2,130 winning scenes belong to 1,281 quests and name 8,784
dialogue topics.
