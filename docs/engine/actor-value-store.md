---
type: Subsystem
title: Actor value store
description: How actor values change at runtime - current values, the override table of base
  offsets and modifier slots, the rule that a base write is a delta over the records, the Papyrus
  writes, regeneration, the HUD bars, and saving.
tags: [engine, actors, gameplay, stats, runtime-state, hud, papyrus]
---

# Actor value store

The baselines come from records ([actor values](/engine/actor-values.md)). This page covers what a
session does to them. The store is a world state component ([runtime state](/engine/runtime-state.md)).

## Current values

The component stores the current health, magicka, and stamina, and not their maximums. A maximum is
a pure function of the `RACE`, `CLAS`, and `NPC_` records. Storing it would let a save keep a number
a changed load order no longer gives. So maximums are derived again, never saved, like the inventory
and quest baselines.

Every stored value is finite and not negative. The component's initializer enforces it, so the
runtime, the HUD, and the save can each rely on it, and the save decoder can pass broken floats
straight in.

Zero health is derived, not stored. A stored flag and a stored health could disagree, and after a
save round trip nothing would say which is right.

Nothing in the runtime throws. A negative or NaN damage amount is ignored, an unknown actor falls
back to a baseline, and every write is clamped. This is runtime state, not file parsing: an actor
that cannot be hit because a write threw is worse than one that takes a clamped hit. A refused write
writes nothing at all. Otherwise a zero-damage call would write the baseline back and mark a clean
reference as changed.

The player has no record here, so its baseline comes from a configured race, with 100/100/100 as the
fallback until character creation exists. That fallback was read from the install: every playable
vanilla race gives 50/50/50, and the vanilla `Player` record (`00000007`) adds +50 to each through
its `ACBS` offsets.

## The override table

Besides the three current values, the component holds a sparse table keyed by vanilla table index.
An actor has 164 values, and a session touches a few. A dense table would save a number for every
value a record gives. An index missing from the table reads its baseline. An override that returns
to nothing is removed, not kept at zero: an actor whose fire resistance went up and back down is an
actor nothing happened to.

Each entry is a base offset plus three modifier slots. The slot names are the scripting API's own:
"While GetActorValue returns the current value, SetActorValue sets the base value ... Any modifiers
are left intact." (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>)

| Slot | Written by | Saved |
| --- | --- | --- |
| Base offset | `SetActorValue`, a skill advance, an attribute pick | Yes |
| Permanent | `ModActorValue` and `ForceActorValue` | Yes |
| Temporary | An active magic effect | No. The effect sets it again on load |
| Damage | `DamageActorValue`. Never positive | Yes |

The eighteen `Skill Advance` slots (indices 114 to 131) hold skill experience, one per skill in the
same order ([skill advancement](/engine/skill-advancement.md)).

Callers read a resolved entry: an absolute base plus the three modifiers. The store builds it from
the baseline on the way out and takes it apart on the way in, so nothing outside the component knows
that a stored base is a distance.

The current value of any other value is derived, never stored, for the same reason as zero health.
Damage moves the damage slot and stops the current value at zero. Restore moves it back toward zero
and stops there, so a restore can never lift a value above its base and modifiers.

A primary (health, magicka, stamina) is the one kind whose current value is stored. The HUD, the
save, combat damage, and the death check all read it. The table adds the ceiling above it:

```text
base(primary)    = derived maximum + base offset
maximum(primary) = base + permanent + temporary
current(primary) = the stored number, clamped to 0 ... maximum
```

So the damage slot is never written for a primary: its damage is already the gap between current and
maximum. A write that moves a primary's maximum moves the current value by the same amount. That is
documented: "ModActorValue is distinct from DamageActorValue because it adjusts the maximum value for
the AV, while DamageActorValue or RestoreActorValue only adjust the current value. For example, if
an actor has 100 Health, ModActorValue by -10 will lower the health total to 90/90, whereas
DamageActorValue by 10 will result in 90/100 Health."
(<https://ck.uesp.net/wiki/ModActorValue_-_Actor>) Damage already taken is kept: an actor at 90/100
modified by -10 reads 80/90.

A timed Fortify Health, Magicka, or Stamina effect writes the temporary slot, so the bar's ceiling
rises and falls with it. At expiry a living actor is left at 1, not 0, when the lost ceiling would
empty the value ([active effects](/engine/magic.md)).

## A base write is a delta

A base override is added to the baseline derived again from records. It never replaces it. The
records say what a value is. The store says only what the session did to it. The two are added on
every read. This one rule decides every case:

- A level change, a race change, or a new load order derives the baseline again, and every value
  moves with it. Nothing keeps a number a plugin no longer gives.
- A trained or script-set value is never overwritten by that, because it was stored as a distance.
- A trained value still gains from a level-up, because the derived part moved under it. A skill
  trained by five points stays five points above whatever the records now give.
- An override of zero is not stored, so an actor that ended where it started is clean in the save.

Storing an absolute base was rejected. It keeps a trained skill safe, but freezes it: a level-up
would raise the derived skill under a fixed number and change nothing, and a load order that
rebalanced a race would be invisible to every actor the session touched.

The skill advance call checks that the index is one of the eighteen skills. A skill advance that
lands on `Aggression` because of an off-by-one index is a bug, and it fails loudly at the one call
that only ever means a skill.

## Writing from Papyrus

| Native | Writes | Quoted behavior |
| --- | --- | --- |
| `SetActorValue` | The base offset | "Sets the base value ... Any modifiers are left intact." |
| `ModActorValue` | The permanent modifier | "adjusts the maximum value for the AV" |
| `ForceActorValue` | The permanent modifier | Forces the current value to the number asked for |

The `ForceActorValue` example pins the whole model: "If an actor has a base health of 125 and you
force their health to 0, then the permanent modifier will be set to -125, and their current health
will become 0. If you then set the base health to 150, they will still have a permanent modifier of
-125, so their current health will instantly become 25 (150 - 125)."
(<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>) OpenSky answers 0/0 and then 25/25.

A negative argument passes through as negative. That is the opposite of `DamageActorValue`, and it
is on purpose: the wiki's own `ModActorValue` example uses -10. Health that reaches zero through any
of the three is a death on the same call, like a fatal blow. So a script that forces health to zero
and then asks `IsDead()` does not see a living actor on the floor. `SetAV`, `ModAV`, and `ForceAV`
are Papyrus wrappers and need no registration.

## Regeneration

The rates come from `RACE` `DATA`: "Health Regen: The percentage of total Health that is regenerated
each second" (<https://ck.uesp.net/wiki/Race>). So one step adds `maximum * percent / 100 * step`.

Regeneration runs on a 1/60 s fixed step, like the Papyrus VM, on the same world update. A paused
frame gives zero time, and zero time does nothing, so menu pause needs no extra code. Negative or
non-finite time is treated the same way. A long stall runs at most eight steps. Actors are updated in
sorted order, so the result does not depend on how they were collected.

Health does not regenerate at zero. An actor at zero is dead or bleeding out, and that is for
[death](/engine/ragdoll.md) to decide. Only the player and actors in loaded cells regenerate. An
actor in an unloaded cell is not simulated.

Three game settings slow it in combat (values from `Skyrim.esm`):

| Setting | Value | Effect |
| --- | --- | --- |
| `fCombatHealthRegenRateMult` | 0 | NPC health in combat. "Most NPCs do not regenerate health during combat" |
| `fCombatMagickaRegenRateMult` | 0.33 | 3% a second becomes 0.99% (UESP "Skyrim:Magicka") |
| `fCombatStaminaRegenRateMult` | 0.35 | 5% a second becomes 1.75% (UESP "Skyrim:Stamina") |

The player's health uses its `Combat Health Regen Multiply` actor value instead, which UESP gives
as 0.7: "0.70% of your maximum health each second outside of combat and 0.49% during combat"
("Skyrim:Health"). No record sets it, so OpenSky starts it at 0.7. The player is in combat while
any actor fights it, because every fight in OpenSky is against the player.

Damage pauses the damaged value: `fDamagedHealthRegenDelay`, `fDamagedMagickaRegenDelay`, and
`fDamagedStaminaRegenDelay` (0.5 s each), and `fDamagedAVRegenDelay` (1 s) when one of them is
missing. The pause is not saved. Casting stops magicka ([spellcasting](/engine/spellcasting.md)).

Each step rewrites the whole component and keeps the override table, so a buff survives. Refill
fills to the effective maximum and keeps the table. "Reset to records" drops it.

## Stamina use

UESP "Skyrim:Stamina" gives the costs. `StaminaSettings` reads them from the install.

```text
sprint, per second = fSprintStaminaDrainMult * (fSprintStaminaWeightBase
                     + wornWeight * fSprintStaminaWeightMult)
block              = fStaminaBlockBase + fStaminaBlockDmgMult * incomingDamage
```

With the vanilla 7, 1, and 0.02, a sprint costs 7 a second plus 2% for each unit of worn
weight. Worn weight is the summed weight of every equipped item. A sprint costs nothing while the
player stands still. When the bar is empty, the sprint key runs instead; it sprints again once
regeneration refills the bar. Each drain is damage, so it also starts the pause after damage
above.

A blocked blow costs the blocker stamina, for the player and for an NPC. `incomingDamage` is the
blow before the block: base damage, fortify bonus, skill, sneak, and armour
([melee damage](/engine/melee-damage.md)). UESP says only that a block uses "a small amount" of
stamina, so the meaning of `incomingDamage` is read from the setting's name.

## HUD bars

The engine turns current values and maximums into HUD meter values and only sends them on a change,
so a still HUD is not drawn again every frame. This lives in the engine, not the AppKit controller,
so a test can damage the player and watch the meters with no window. An actor with a zero maximum
shows an empty bar, never a full one.

## Saving

Current values go in the `AVAL` chunk, one entry per actor that differs from a full baseline. The
override table goes in `AVOV`, and each `AVOV` entry travels beside that actor's `AVAL` entry. The
temporary slot is not saved: the active effect sets it again on load, and saving both would double
the buff. The layouts, and why these are separate chunks, are on the
[save chunks](/formats/opensky-save-actor-chunks.md) page.

Maximums are not saved. So a save loaded against changed records gets the new numbers. The stored
current value is kept, and the first change clamps it into the new range.
