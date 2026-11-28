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
([shared field groups](../formats/records.md#shared-field-groups)):

| Field | Bytes | Meaning |
| --- | --- | --- |
| `DEST` | 8 | health (Int32), stage count, VATS targetable, unknown (UInt16) |
| `DSTD` | 20 | health percent, index, model damage stage, flags, self damage per second (Int32), explosion, debris, debris count (Int32) |
| `DSTF` | 0 | end of one stage |

Stage flags: 0x01 cap damage, 0x02 disable, 0x04 destroy, 0x08 ignore external damage.

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

The state lives in the [script state](papyrus-script-state.md), so it is saved, and
the conditions `GetDestroyed` and `GetDestructionStage` read it.

## In the game

Damage does nothing when the reference is disabled or deleted, when its model is not loaded, when
the damage is 0 or less, or when its health is already 0.

The health percent is the health left divided by the full health, times 100. The stages are checked
in their order in the record. A stage is reached when its health percent is at or above the new
health percent.

- A stage with the cap flag holds the health at its percent, so one hit cannot pass it.
- A next stage with the Ignore External Damage flag also holds the health at the current stage,
  unless the damage is forced, such as from a script.
- While the current stage has Ignore External Damage, damage that is not forced does nothing.

Example: full health 100, stages at 66 and 33 percent. A hit of 50 leaves 50 percent, so the
66 percent stage is reached. With the cap flag on that stage, the health stays at 66.

On a new stage:

1. The model changes. A stage with a `DMDL` model swaps to it. Otherwise the `NIF` switches to the
   stage's model damage stage.
2. A stage with self damage per second keeps damaging the reference each second while health is
   above 0.
3. For each stage passed, in order:
   - disable: the reference is disabled; a projectile is removed instead;
   - destroy: the reference is marked destroyed;
   - debris: the stage's debris count of pieces appear at the reference;
   - explosion: the stage's explosion goes off at the centre of the reference's bounds, moved by a
     random amount within the bound radius. Its source is the reference, or for a projectile, the
     shooter and the weapon.
4. `OnDestructionStageChanged(old, new)` fires.

Damage comes from:

- a weapon hit, the same damage as on an actor;
- an explosion, its damage times its falloff ([explosions](explosions.md#damage));
- a physics impact, such as a thrown object.

Whether a spell without an explosion deals destruction damage was not found.

## Where OpenSky differs

- Spells without an explosion deal no destruction damage.
- A fast body damages a destructible object it touches, with the same damage it deals an actor
  ([impulses](impulses.md#physics-damage)). The body itself takes no destruction damage
  from the impact.
