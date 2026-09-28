---
type: Subsystem
title: Magic and active effects
description: How a magic effect acts on an actor - where the rules come from, the two timed
  behaviors the Recover flag chooses, which archetypes run, the expiry floor, ticking, condition
  gating, stacking, drinking a potion or eating an ingredient, and what a save keeps.
tags: [engine, magic, effects, actors, alchemy]
---

# Magic and active effects

An active effect is a decoded [`MGEF`](/formats/magic-records.md), with the `EFIT` numbers beside
it, acting on an actor. It moves that actor's [actor values](/engine/actor-values.md) and ends by
itself. This page covers effects once they are applied.

Related pages:

- [Spellcasting](/engine/spellcasting.md): knowing spells, readying them, and casting.
- [Spell delivery](/engine/spell-delivery.md): spells that leave the caster, and resistances.
- [AI spell use](/engine/ai-spell-use.md): NPCs casting in a fight.
- [Item enchantments](/engine/item-enchantments.md): weapon charge and worn effects.

## Sources

Nothing here is from memory. The rules come from:

- The Creation Kit wiki's Magic Effect page, for the flags and the archetype table
  (<https://ck.uesp.net/wiki/Magic_Effect>). The live site refuses automated requests, so it is read
  through the Wayback Machine ([environment](/tools/environment.md)).
- UESP's Mod File Format/MGEF page, for the `DATA` layout and the flag bits
  (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>).
- UESP's Alchemy Effects page, for the ingredient rule
  (<https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>).

Where a source is unsure, that is written down, not guessed.

## The two timed behaviors

The Recover flag decides how a timed effect works. The Creation Kit page says:

> Recover: When this Effect expires, the attribute returns to its previous state. If checked,
> Value Modifier and Peak Value Modifier archetypes will modify their actor value once at the
> start, then modify it back once the Effect expires; if unchecked, the actor value will get
> modified every second and will not be reset at the end. Note that for Magicka and Health, this
> works as follows: If checked, the Maximum and Current values are changed (buff/debuff). If
> unchecked, only current value is affected (heal/damage).

So a timed effect has one of two modes:

- Modifier (Recover set): the magnitude is added to the value's temporary modifier slot when the
  effect starts, and taken away when it ends or is dispelled. Each effect records how much of the
  slot it owns, so two overlapping buffs each give back exactly what they put in.
- Per second (Recover clear): the magnitude is paid into the value once per completed second and
  never taken back. A ten-second effect of magnitude two pays twenty points, the first two one
  second after it starts. The count of paid seconds is stored, so many small steps cannot round
  into an extra payment.

The simulation step is 1/60 s, which has no exact binary value, so sixty steps add up to slightly
less than one second. An effect snaps to its duration once less than half a step remains, and a
second counts as paid within a millisecond. Without both, an effect would take one extra step to end,
and a per-second effect would skip its last payment. The tests caught both.

A zero-duration effect is neither. It applies once and is stored nowhere, so a restore health potion
never appears in the active effect list. The direction comes from the Detrimental flag: "This Effect
is applied as a negative value (damage) to the specified Actor Value". A detrimental effect damages
the value, and any other restores it.

The No Magnitude, No Area, and No Duration flags are ignored. The same page says why: "No
Magnitude, No Area and No Duration do not actually affect the inner workings of the effect, checking
them just makes it so these parameters will be unavailable when you assign the effect". The `EFIT`
numbers are used as written.

## Which archetypes run

Three. Every other archetype applies nothing and adds to a count per archetype, so the missing work
is measured.

| Archetype | Quoted behavior | What OpenSky does |
| --- | --- | --- |
| Value Modifier (0) | "Modifies the Actor Value by `<MAG>`." | Moves the `MGEF` primary actor value by the `EFIT` magnitude |
| Dual Value Modifier (5) | "The first value is modified by `<MAG>`, the second value is modified by `<MAG>` * AV Weight." | Moves two values, the second scaled by the second AV weight |
| Peak Value Modifier (34) | "1: The value to modify. 2: A keyword for effects it does not stack with." | Moves one value, and keeps the keyword the stacking rule compares |

Instant restore and damage are not separate archetypes. Both are Value Modifier entries with zero
duration, which is what vanilla Restore Health and Damage Health are. A record that names no actor
value in the vanilla table (usually -1, "none") applies nothing and has its own count.

A timed Recover effect on health, magicka, or stamina changes both the maximum and the current value,
as the Creation Kit says. It holds its magnitude in the temporary slot
([actor value store](/engine/actor-value-store.md)). The maximum rises, the current value rises with
it, and damage taken in the meantime is kept: 125 maximum with 60 taken reads 40 of 100 once the
effect ends.

## The expiry floor

UESP's [Fortify Health](https://en.uesp.net/wiki/Skyrim:Fortify_Health) page: "When the effect
expires, the target loses <mag> points of health unless that would reduce the target's health to 0
or less (the target is left with at least 1 health point when the effect expires)." So an ending
effect leaves a living actor at 1 at least, and a timer never kills. An actor already at zero stays
at zero: the floor protects the living and does not revive the dead. A worn Fortify Health
enchantment coming off takes the same path.

UESP states this for health only. OpenSky applies it to magicka and stamina too, because they share
the storage and the release path, and a timer that leaves a living actor at zero magicka would be
the same invented loss.

## The component

An actor's effects are a world state component, in the order they were applied
([runtime state](/engine/runtime-state.md)). It is separate from the actor value component because
the two change at different rates: current health is written sixty times a second, and the effect
list only when something is applied, ends, or is dispelled.

Each effect holds its source (potion, ingredient, spell, or enchantment, with the record key), the
`MGEF`, the caster if there is one, its mode, its duration and elapsed time, and one entry per actor
value it moves. Effects are numbered per actor, not globally, so two doses of the same potion are
two effects, and the numbers survive a save with no counter in the save. The component is removed
once it is empty.

## Ticking

Effects advance in whole 1/60 s steps, at most eight per frame, on the same world update as
regeneration and the Papyrus VM. A paused frame gives zero time, so nothing advances in a menu. The
player and actors in loaded cells tick. An actor in an unloaded cell is not simulated.

Regeneration rewrites the whole actor value component every frame. It keeps the override table
through that write. Without that, a held modifier would last exactly one frame.

## Conditions

An effect entry's `CTDA` list is evaluated against the target when the effect is applied, with both
run-ons naming the receiving actor ([condition evaluation](/engine/conditions.md)). An
empty list is true. A list OpenSky cannot evaluate is a false with a reason, and the entry is
skipped and counted, never passed quietly.

Conditions on the `MGEF` itself are not evaluated yet. The Creation Kit separates the two, and the
difference matters for held spells.

## Stacking

Two applications of the same effect are two effects, and each holds its own share of the slot. Two
rules change that:

- No Recast: "Once the magic effect is applied to a target, it cannot be cast again on the same
  target until it has worn off or been dispelled." A second application while the first runs is
  refused and counted.
- Peak Value Modifier keywords: "If there are two PVMs with the same keyword active at the same
  time, the one with the lower `<mag>` will be dispelled automatically?" The question mark is the
  wiki's own. OpenSky follows the rule as written: the stronger stays, the weaker is dispelled, and
  an incoming weaker one is refused. The doubt is real.

Tapering is not applied. The Creation Kit documents it, but no vanilla potion or ingredient effect
uses it, so it would be untested.

## Potions and ingredients

Consuming removes one unit through the inventory and applies what the item does. The unit is only
removed on success. A consume that applies nothing, because the effect is not implemented, still uses
the unit, as drinking such a potion does in the game.

`ALCH` applies its whole effect list. `INGR` applies only its first effect. UESP:

> Ingredients listed in bold have that effect as their first, meaning that eating a sample of that
> ingredient will provide a small version of that effect.

Which effects eating an ingredient reveals is a different question: the Experimenter perk changes
it, and it belongs to alchemy, not to applying effects.

## Saving

Timed effects go in the `AEFF` chunk ([save chunks](/formats/opensky-save-actor-chunks.md)). It
stores elapsed time, not remaining time, so a loaded effect shows the same total duration as before.

The `AVOV` chunk leaves out the temporary slot, because saving both it and the effect behind it
would double every buff. Each saved effect records how much of the slot it owns, and the slot is
rebuilt from that after a load. Instant effects are not saved: they already moved a value, and the
value is saved.

The rebuild runs for the player only. When the player's state loads, the cells have not streamed
back in, so no other actor has a holder yet. An NPC with a timed effect across a load keeps the
effect but not its modifier. That is a known gap.

## Controls

World > Combat & Physics > Magic Effects sits beside Actor Values, because a potion that restored
health is only convincing next to the health.

- Consume carried item: consumes the first `ALCH` or `INGR` the player carries. The inventory menu's
  Consume button uses the same path ([inventory menu](/engine/inventory-menu.md)).
- Dispel: acts on the player only. A dispel is a way back from something the user did, and the
  nearest actor's effects belong to the world.
- Readout: the player's effects first, then the nearest actor's, the same actor the Actor Values
  panel names. "No actor nearby" and "an actor with nothing running" read differently, so an NPC just
  hit by a spell and an empty cell cannot look the same.

Effect visuals and sounds are not drawn or played. The `ALCH` consume sound is decoded and passed
along for when they are.
