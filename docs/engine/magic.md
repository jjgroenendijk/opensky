---
type: Subsystem
title: Magic and active effects
description: The runtime notion of a magic effect acting on an actor - the cited
  archetype semantics, the two timed behaviours the Recover flag selects, the
  component and its AEFF save chunk, condition gating, the stacking rules, and
  the potion and ingredient consumption path that is the first consumer.
tags: [engine, magic, effects, actors, alchemy]
timestamp: 2026-08-16T00:00:00Z
---

# Magic and active effects

Roadmap item 19.6, issue #469. The first runtime magic in OpenSky: a decoded
[MGEF](/formats/magic-records.md) plus the EFIT numbers beside it becomes something acting
on an actor, moving that actor's [actor values](/engine/actor-values.md) and expiring on its
own. Casting is not here — issues 19.7 and 19.8 own that, and this subsystem applies effects
handed to it.

## Contents

- [Where the semantics come from](#where-the-semantics-come-from)
- [The two timed behaviours](#the-two-timed-behaviours)
- [Which archetypes are implemented](#which-archetypes-are-implemented)
- [The component](#the-component)
- [Ticking](#ticking)
- [Condition gating](#condition-gating)
- [Stacking](#stacking)
- [Consuming a potion or an ingredient](#consuming-a-potion-or-an-ingredient)
- [The AEFF save chunk](#the-aeff-save-chunk)
- [Verification](#verification)
- [Limits / next](#limits--next)

| Layer | File | Target |
|---|---|---|
| Model | `opensky/Engine/Magic/ActiveEffect.swift` | app + CLI |
| Component | `opensky/Engine/Magic/ActiveEffectComponent.swift` | app + CLI |
| Archetype dispatch | `opensky/Engine/Magic/MagicEffectPlanner.swift` | app + CLI |
| Runtime | `opensky/Engine/Magic/ActiveEffectRuntime.swift` | app + CLI |
| Consumption | `opensky/Engine/Magic/MagicItemConsumption.swift` | app + CLI |
| Coverage tally | `opensky/Engine/Magic/ActiveEffectTally.swift` | app + CLI |
| Save chunk | `opensky/Engine/Formats/Save/OpenSkySave{Encoder,Decoder}ActiveEffects.swift` | app + CLI |
| Panel seam | `opensky/Engine/MagicEffectControlProviding.swift` and `MagicEffectControlReadout.swift` | app + CLI |
| Session wiring | `opensky/App/GameViewControllerMagic.swift` and `GameViewControllerMagicPanel.swift` | app |
| Verification surface | `opensky/App/Shell/Sections/CombatMagicEffectsSection.swift` | app |

## Where the semantics come from

Nothing on this page is recalled from memory. Two open sources carry the behaviour:

- The Creation Kit wiki's **Magic Effect** page, for the flags and the Effect Archetypes
  table (<https://ck.uesp.net/wiki/Magic_Effect>). The live host refuses automated
  requests, so it is read through the Wayback Machine — see
  [environment notes](/tools/environment.md).
- UESP's **Mod File Format/MGEF** page, for the DATA layout and the flag bits
  (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>).
- UESP's **Alchemy Effects** page, for the ingredient rule
  (<https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>).

Where a source hedges, the hedge is recorded rather than resolved by guessing; see
[Stacking](#stacking) and [Limits / next](#limits--next).

## The two timed behaviours

The Recover flag decides everything about how a timed effect works. The Creation Kit page
states it directly:

> Recover: When this Effect expires, the attribute returns to its previous state. If checked,
> Value Modifier and Peak Value Modifier archetypes will modify their actor value once at the
> start, then modify it back once the Effect expires; if unchecked, the actor value will get
> modified every second and will not be reset at the end. Note that for Magicka and Health,
> this works as follows: If checked, the Maximum and Current values are changed
> (buff/debuff). If unchecked, only current value is affected (heal/damage).

So `ActiveEffectMode` has exactly two cases:

- **`modifier`** (Recover set): the magnitude is added to the actor value's **temporary**
  modifier slot when the effect starts and subtracted again when it expires or is dispelled.
  Each stored effect records how much of the slot it owns, so two overlapping buffs hand back
  exactly what each of them put in.
- **`perSecond`** (Recover clear): the magnitude is paid into the value once per **completed**
  second and never taken back. A ten-second effect of magnitude two takes twenty points, the
  first two landing one second after it was applied. The count of seconds already paid is
  stored rather than derived from elapsed time alone, so repeated small ticks cannot round
  into an extra payment.

One arithmetic detail is stated because it is a real failure the suites caught rather than a
theoretical one: the simulation step is 1/60 s, which has no exact binary representation, so
sixty steps sum to slightly under one second. An effect is snapped to its duration once less
than half a step remains, and a whole second counts as paid within a millisecond of elapsing.
Without both, an effect would take one extra step to expire and a per-second effect would skip
its last pay-out.

A **zero-duration** effect is neither. It applies once and is stored nowhere, which is why
`ActiveEffectMode` has no `instant` case and why a restore-health potion never appears in the
active-effect list. Direction comes from the Detrimental flag — "This Effect is applied as a
negative value (damage) to the specified Actor Value" — so a detrimental effect routes
through `ActorValueRuntime.damage` and a restorative one through `restore`.

The No Magnitude, No Area and No Duration flags are deliberately ignored when applying. The
same page says why: "No Magnitude, No Area and No Duration do not actually affect the inner
workings of the effect, checking them just makes it so these parameters will be unavailable
when you assign the effect". The EFIT numbers are taken as authored.

## Which archetypes are implemented

Three, and every other archetype applies nothing and increments a per-archetype tally so the
unimplemented ground is measured rather than silent.

| Archetype | Cited behaviour | What OpenSky does |
|---|---|---|
| Value Modifier (0) | "Modifies the Actor Value by `<MAG>`." | One value, the MGEF's `PrimaryAV`, moved by the EFIT magnitude |
| Dual Value Modifier (5) | "The first value is modified by `<MAG>`, the second value is modified by `<MAG>` * AV Weight." | Two values, the second scaled by `SecondAVWeight` |
| Peak Value Modifier (34) | "1: The value to modify. 2: A keyword for effects it does not stack with." | One value plus the keyword the stacking rule compares |

Instant restore and damage are not separate archetypes: both are Value Modifier entries with
a zero duration, which is what the vanilla Restore Health and Damage Health effects are.

Two more reasons an implemented archetype still applies nothing, each its own tally bucket:

- The record names no actor value inside the vanilla table (usually -1, "none").
- A **timed Recover effect names health, magicka or stamina**. The Creation Kit says that
  changes both the maximum and the current value, and item 19.5 deliberately left the three
  primaries without the base-plus-modifiers storage the other 161 values have
  ([actor values](/engine/actor-values.md)), so there is nowhere to hold the change. It is
  counted rather than approximated: moving current health for a "fortify health" effect would
  be a different effect wearing the same name.

## The component

`ActiveEffectState` is a [world-state component](/engine/runtime-state.md) in the
`activeEffects` slot, holding one actor's effects in ascending application order. It is a slot
of its own beside `actorValues` for the lifetime reason `death` and `combat` are separate
slots: a current-health float is rewritten sixty times a second, while an effect list changes
only when something is applied, expires or is dispelled.

Each `ActiveEffect` carries its source (potion, ingredient, spell or enchantment, plus the
record key), the MGEF it is an application of, the applying actor where one exists, its mode,
its duration and elapsed time, and one entry per actor value it acts on. Applications are
numbered per actor rather than globally, so two applications of the same potion are genuinely
two effects and the number survives a save round trip without the save carrying an allocator.

The component is dropped entirely once it empties, so an actor whose effects all expired stops
being dirty for this slot.

## Ticking

`ActiveEffectRuntime.advance(delta:accumulator:over:)` runs whole 1/60 s steps, capped at
eight per frame, exactly as `ActorValueRuntime` regeneration does. It shares
`Renderer.onWorldUpdate` with regeneration and the Papyrus VM, so a menu-paused frame delivers
delta 0 to all three and none of them advances — the established rule.

The tick set is the player plus every resident actor, the same set regeneration advances: an
actor in a cell that is not loaded is not simulated at all in this engine.

One consequence worth stating, because it was a real bug this item fixed:
`ActorValueRuntime`'s regeneration step rewrites the whole actor-value component every frame,
and it now carries the general table through that write. Without that, a held modifier would
survive for exactly one frame.

## Condition gating

An effect entry's `CTDA` list is evaluated against the target at application time through the
same [`ConditionEvaluator`](/engine/runtime-state.md) every other site uses, with both run-ons
naming the receiving actor. An empty list is true, which is what an unconditioned entry means.
A list this engine cannot evaluate is the documented reason-tagged false and the entry is
skipped and counted — never a silent pass.

Conditions on the MGEF itself are not evaluated yet; see [Limits / next](#limits--next).

## Stacking

Two applications of the same effect are two effects and both hold their own share of the
modifier slot. Two rules override that:

- **No Recast.** "Once the magic effect is applied to a target, it cannot be cast again on the
  same target until it has worn off or been dispelled." A second application while the first
  runs is refused and counted.
- **Peak Value Modifier keywords.** "If there are two PVMs with the same keyword active at the
  same time, the one with the lower `<mag>` will be dispelled automatically?" — the question
  mark is the wiki's own. OpenSky implements the rule as written: the stronger survives, the
  weaker is dispelled, and an incoming weaker one is refused rather than displacing the
  stronger. **The uncertainty is real and is recorded here rather than hidden.**

## Consuming a potion or an ingredient

`ActiveEffectRuntime.consume` is the first consumer. It removes one unit through
[`InventoryRuntime`](/engine/runtime-state.md) and applies what the item does to the target.
The removal happens only on success, and a consume that applies nothing still costs the unit —
which is what drinking a potion of an unimplemented effect does in the original game.

ALCH applies its whole effect list. INGR applies **only its first effect**, which UESP states:

> Ingredients listed in bold have that effect as their first, meaning that eating a sample of
> that ingredient will provide a small version of that effect.

Which effects eating an ingredient *reveals* is a different question — the Alchemy skill's
Experimenter perk changes it — and that is discovery state belonging to the alchemy milestone,
not application.

Reachable two ways, both routing through the same `GameViewController.consumeMagicItem` so
they cannot diverge: the **Consume** button in
[World > Inventory Menu > Menu](/engine/inventory-menu.md), which acts on the selected row,
and the **Consume carried item** button in the panel section below, which acts on the first
ALCH or INGR the player carries.

## The AEFF save chunk

Additive and split out of `RDLT` for the same reason `AVAL` and `DETH` are. One entry per
actor carrying timed effects, each listing the effects with their remaining duration; a
session in which nothing was applied writes no chunk at all.

Per effect, in order: the sequence, the source kind, the source record key, the MGEF key, an
optional caster key, the mode, the detrimental byte, the duration, the elapsed seconds, the
seconds already paid out, an optional stacking keyword, then one `(index, magnitude, applied)`
record per actor value.

The chunk stores `elapsed` rather than "remaining" so a reloaded effect reports the same total
duration a readout showed before the save.

**This chunk is what makes `AVGN`'s dropped temporary modifier recoverable.** The general
actor-value chunk deliberately does not persist the temporary slot, because persisting both it
and the effect that established it would double every buff on reload. Each stored effect
records how much of the slot it owns, and `reestablishModifiers(on:)` rebuilds the slot from
that after a load.

Instant effects are not in the chunk and cannot be: a zero-duration effect moved an actor value
once, and the moved value is what `AVAL` and `AVGN` already carry.

Tolerance follows the container's rules. An unknown chunk is skipped by its declared length, a
degenerate effect (zero duration, no values) is normalized away by the type rather than failing
a load, and an unknown source kind or mode is the one hard stop — both are closed enumerations
this build wrote itself.

## Verification

Sidebar path **World > Combat & Physics > Magic Effects**
(`Destination-combatPhysics`, `PanelSection-combatMagicEffects`). Controls:
`MagicEffectConsumeControl`, `MagicEffectDispelControl`. Readout:
`CombatMagicEffectsStatsLabel`. It sits beside Actor Values because that is what it acts on: a
potion that restored health is only convincing next to the health it restored.

The inventory menu's own action is `InventoryMenuConsumeControl` under
**World > Inventory Menu > Menu**.

Covering tests:

- `MagicEffectPlannerTests` — archetype dispatch, the dual-value weight, the Recover mode
  split, the Peak Value Modifier keyword, and each skip reason.
- `ActiveEffectRuntimeTests` — instant restore and damage, the held modifier and its exact
  reversal, per-second pay-out, condition-gated skip, both stacking rules, dispel,
  `HasMagicEffect`, modifier re-establishment after a load, and that regeneration does not drop
  a held modifier.
- `MagicItemConsumptionTests` — drinking a potion through `InventoryRuntime`, the ingredient
  first-effect rule, and the two refusals.
- `ActiveEffectSaveTests` — the round trip, the modifiers a restored effect owns, no chunk for
  a session with no effects, and the unknown-source-kind hard stop.
- `CombatMagicEffectsPanelTests` — accessibility ids, control routing, and the readout with and
  without a runtime.

## Limits / next

- **Casting is not here.** Issues 19.7 and 19.8 own spells; this subsystem applies effects
  handed to it. `ActiveEffectSourceKind` already carries `spell` and `enchantment` cases so
  those milestones add a caller rather than a concept.
- **Enchantment triggers** are issue 19.9.
- **Tapering is not applied.** The Creation Kit documents the taper weight, curve and duration
  formula, but no vanilla potion or ingredient effect this item consumes uses it, so
  implementing it here would be untested ground.
- **MGEF-side conditions are not evaluated**, only the effect entry's own list. The Creation
  Kit distinguishes the two and the distinction matters for concentration spells, which is
  casting's problem.
- **A timed Recover effect on a primary is counted, not applied.** It needs the
  base-plus-modifiers storage for health, magicka and stamina that item 19.5 declined to build;
  see [actor values](/engine/actor-values.md).
- **`HasMagicEffect` is answerable but not registered.** The component answers the query;
  registering the condition function and the Papyrus native is issue 19.11.
- **Visuals and sounds** for effects are milestone M26. The ALCH consume sound is decoded and
  carried through `MagicItemUse` for the milestone that plays it.
