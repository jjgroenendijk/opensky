---
type: Subsystem
title: Papyrus destruction
description: How damage from a script moves a reference through the destruction stages of its
  base form, and where OpenSky differs from the game.
tags: [engine, papyrus, destruction]
---

# Papyrus destruction

A base form with `DEST` data, such as an activator or a moveable static, can break in stages.
Scripts drive it with `DamageObject`, `SetDestroyed`, `ClearDestruction`, and
`GetCurrentDestructionStage`, and they hear a change through
`OnDestructionStageChanged(int aiOldStage, int aiCurrentStage)`. Signatures come from the
Creation Kit wiki page "ObjectReference Script".

## Data

The record layout comes from xEdit `wbDefinitionsTES5.pas`
([shared field groups](/formats/records.md#shared-field-groups)):

| Field | Bytes | Meaning |
| --- | --- | --- |
| `DEST` | 8 | health (Int32), stage count, VATS targetable, unknown (UInt16) |
| `DSTD` | 20 | health percent, index, model damage stage, flags, self damage per second (Int32), explosion, debris, debris count (Int32) |
| `DSTF` | 0 | end of one stage |

Stage flags: 0x01 cap damage, 0x02 disable, 0x04 destroy.

## The stage rule

Damage adds up on the reference. A stage is reached when the health left falls to its
percent of the full health or lower:

```text
health - damage <= health * healthPercent / 100
```

Example: health 100, a stage at 50 percent and one at 0 percent. 60 damage reaches the 50
percent stage. 40 more reaches the 0 percent stage.

- A stage with the cap flag keeps health at its percent, so damage stops there.
- A stage with the destroy flag marks the object destroyed. Further damage does nothing.
- A stage with the disable flag disables the reference.
- `SetDestroyed(true)` jumps to the last stage. `SetDestroyed(false)` and `ClearDestruction`
  make the object whole again.

The state lives in the [script state](/engine/papyrus-script-state.md), so it is saved, and
the conditions `GetDestroyed` and `GetDestructionStage` read it.

## Where OpenSky differs

- Only scripts deal destruction damage. Weapons, spells, and explosions do not damage
  destructible objects yet.
- A stage change does not swap the model, spawn debris, play the explosion, or apply self
  damage over time.
- The order in which the game walks the stages is not documented. OpenSky walks them from
  the highest health percent down and stops at the first one not reached.
