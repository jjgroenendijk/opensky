---
type: Subsystem
title: Magic effect archetypes
description: What each MGEF archetype does in OpenSky, where each rule comes from, how the
  archetypes reach the combat loop and the world, and which archetypes still do nothing.
tags: [engine, magic, effects, combat, actors]
---

# Magic effect archetypes

An archetype is the code-based behaviour an `MGEF` record picks in its `DATA` block
([magic records](/formats/magic-records.md)). This page lists what each archetype does in
OpenSky. How a timed effect is stored, ticked, and saved is on the
[magic](/engine/magic.md) page.

## Sources

- The Creation Kit wiki's Magic Effect page, archetype table
  (<https://ck.uesp.net/wiki/Magic_Effect>), read through the Wayback Machine
  ([environment](/tools/environment.md)). Every quote below without another link is from it.
- UESP spell pages for numbers the wiki does not give:
  [Ward](https://en.uesp.net/wiki/Skyrim:Ward), [Cloak](https://en.uesp.net/wiki/Skyrim:Cloak),
  [Calm](https://en.uesp.net/wiki/Skyrim:Calm),
  [Absorb Health](https://en.uesp.net/wiki/Skyrim:Absorb_Health),
  [Slow Time](https://en.uesp.net/wiki/Skyrim:Slow_Time),
  [Block](https://en.uesp.net/wiki/Skyrim:Block) for Quick Reflexes, and
  [Conjuration](https://en.uesp.net/wiki/Skyrim:Conjuration) for Twin Souls and Dark Souls.

Where the wiki writes "???" or "Not Used", that is all OpenSky knows.

## Four kinds of rule

Each archetype has one rule (`MagicArchetypeRule`). The rule decides where the archetype acts.

| Kind | Where it acts | Archetypes |
| --- | --- | --- |
| Actor values | The target's actor values, in the effect runtime | Value Modifier, Dual Value Modifier, Peak Value Modifier, Absorb, Accumulate Magnitude, Invisibility |
| Influence | The combat loop, through `ActorMagicInfluence` | Calm, Frenzy, Demoralize, Rally, Turn Undead, Paralysis, Etherealize |
| Effect list | The target's running effects | Dispel, Cure Disease, Cure Poison, Cure Paralysis |
| World | The session, through `MagicWorld` | Stagger, Spawn Hazard, Cloak, Bound Weapon, Disarm, Soul Trap, Slow Time, Summon Creature, Reanimate |

Script, Concussion, and Cure Addiction are carriers. Script "has no effect other than any
Papyrus Scripts specified", and the wiki marks the other two "Not Used". A timed carrier is
stored, so `HasMagicEffect` sees it. Magic effect scripts do not run yet, so a Script effect
does nothing else.

An effect that acts on no actor value still stores one value at index -1 (none) that holds its
`EFIT` magnitude. Cloak reads its radius there, and the save keeps it with no format change.

## Actor values

- Absorb: "Does up to `<MAG>` damage to the target's attribute, and restores the caster's
  attribute by the amount of damage done. If not 'detrimental', will instead drain the caster
  to replenish the target." The caster gets what was taken, not the magnitude: a target with
  10 health left gives 10. A timed absorb pays each second, whatever the Recover flag says,
  because a held modifier cannot move health between two actors.
- Accumulate Magnitude: "Grants up to `<MAG>` of a chosen actor value, but starts at 0 and
  increases over time." UESP's Ward page says a ward charges up over "a period of time of
  about one second". OpenSky grows the value in a straight line over one second. The shape and
  the exact time are estimates.
- Invisibility holds the `Invisibility` actor value at 1, which detection reads. "This effect
  is automatically dispelled when the invisibility is broken". Casting a spell breaks it.
  Attacking and activating do not break it yet.
- Paralysis holds the `Paralysis` actor value at 1, as the wiki says, and is also an influence.
  "This archetype only works if the 'Recover' flag is set", so an effect without Recover is
  counted and does nothing.

A held flag is always +1. The Detrimental flag does not make it -1.

## Influence

The combat loop reads `ActorMagicInfluence` for each actor every step.

| Archetype | Wiki | Combat loop |
| --- | --- | --- |
| Calm | "Lowers the Aggression of a target up to level `<MAG>` to minimum." | Leaves the fight and stands still |
| Frenzy | "Maxes the Aggression of a target up to level `<MAG>`." | Fights the player even when neutral |
| Demoralize | "Lowers the Confidence ... Allies affected by Demoralize prior to combat will not flee until combat begins." | Flees once it perceives the player |
| Turn Undead | "Causes the target to flee from the caster, similar to Demoralize." | As Demoralize |
| Rally | "Maxes the Confidence of a target up to level `<MAG>`." | Never flees, not even when hurt |
| Paralysis | "Paralyzes the target." | Leaves the fight and stands still; the player cannot move |
| Etherealize | "preventing them from dealing or taking damage" | No blow lands from it or on it |

The level cap: Calm, Frenzy, Demoralize, Rally, Turn Undead, and Disarm work "up to level
`<MAG>`". A target above the magnitude is refused and counted. UESP's Calm page shows the
same rule with numbers: magnitude 9 works on "Creatures and people up to level 9".

Turn Undead "is hard-coded to require that the target have the ActorTypeUndead keyword". The
keyword is looked for on the actor's `NPC_` record and on its race.

Calm and Frenzy at once: in the game the later effect wins, because both set one value.
OpenSky lets Calm win. A calmed actor that attacks is the more harmful mistake.

The loop fights only the player ([combat](/engine/combat.md)), so Frenzy cannot make an actor
attack another NPC, and fear runs from the player only.

## Effect list

- Dispel: "Removes magic effects with a duration from the target." Constant effects stay.
- Cure Disease removes effects whose source is a `SPEL` of type Disease.
- Cure Poison removes effects whose source is an `ALCH` with the Poison flag.
- Cure Paralysis removes Paralysis effects. UESP notes Skyrim itself has no Cure Paralysis
  spell.

## World

The effect runtime queues a `MagicWorldAction`, and `MagicCoordinator` carries it out after
the change, through `MagicWorld`. A queue keeps the runtime a value with no world inside it.

- Stagger: "Staggers the target. ... Duration determines how long before the target can be
  staggered again." While a stagger effect runs, a new one is ignored. An NPC plays the combat
  loop's stagger; the player's graph gets `staggerMagnitude` and then `staggerStart`.
- Spawn Hazard: "Creates the specified Hazard object at the target." It goes through the same
  path as Papyrus `PlaceAtMe`. The wiki's magnitude scaling of the hazard spell is not done.
- Bound Weapon: "Creates the specified Weapon, and dispels it when the duration expires or the
  weapon is sheathed." The weapon is added and equipped, then unequipped and removed when the
  effect ends. Sheathing does not end it yet.
- Disarm: unequips every weapon the target holds. In the game the weapon falls to the ground.
  OpenSky keeps it in the inventory, because nothing drops an actor's item yet.
- Cloak: "While this spell is active, casts an effect spell on all targets in the area. ...
  the `<MAG>` of the Cloak effect is not the damage ... but the radius". UESP: cloaks hit only
  actors "hostile to you", and "casting a second will cancel the first". OpenSky casts the
  associated spell once a second on every hostile living actor inside the radius. The rate is
  an OpenSky choice; the wiki names none.
- Slow Time: "Slows time for all but the player by the indicated amount (a multiplier, with 1
  being normal time)." Only the player's own Slow Time effects count. UESP: the player is
  "only slowed down to 70% of normal speed". Perk entry point 70 (Mod Player Magic Slowdown)
  changes that 70% share; Quick Reflexes sets it to 1, and UESP says it "does not partially
  slow the player". Two effects stack, so their shares multiply. The player never runs slower
  than the world, and the world never runs below 1% (an OpenSky floor, so a magnitude of 0
  cannot stop every clock). The session runs the world sim, animation, and particles at the
  world share, and the camera at the player's share.
- The player's effects tick on the player's clock while time is slow, so an 8 second Slow Time
  ends after 8 seconds of the player's time. [WARNING] UESP also says Slow Time "extends the
  duration of potions on the player", which this does not do.
- Summon Creature: "Summons the specified creature, placing them under the caster's control. On
  death, the creature automatically fades out and leaves no corpse." The effect runs on the
  caster. A target-location summon spell places the associated `NPC_` at the aim point, facing
  the caster, as a spawned actor in the caster's cell; the next cell build draws it. When the
  effect ends, the spawn is removed.
- Reanimate: "If the target is dead, reanimate them, putting them under the caster's control."
  Its magnitude is the highest level it raises, as for Calm. A living target ends the effect at
  once. The corpse is resurrected, and it falls dead again when the effect ends. Perk entry
  point 53 (Apply Reanimate Spell) picks a spell for the raised actor, as Dark Souls does.
- A caster commands one summoned or reanimated actor at a time. Perk entry point 68 (Mod
  Commanded Actor Limit) adds to that 1: Twin Souls allows "two atronachs or reanimated
  zombies". Past the limit, the caster's oldest actor goes and its effect ends.
- [WARNING] A commanded actor does not follow its caster or fight for it yet, because NPCs do
  not fight NPCs. Summons are not saved as commanded, and a death does not end the effect.

## Not done

These archetypes have no rule. Each is counted per effect, and `make gaps` ranks them
([gap report](/tools/gaps.md)).

| Archetype | What is missing |
| --- | --- |
| Command Summoned, Banish | Taking or ending control of another caster's summon |
| Detect Life, Light | Drawing a shader or a light on an actor |
| Enhance Weapon | A temporary enchantment on the equipped weapon |
| Werewolf, Vampire Lord, Werewolf Feed | Changing an actor's race |
| Telekinesis, Grab Actor | Holding an object or actor in front of the caster |
| Guide, Spawn Scripted Ref, Lock, Open, Disguise, Value and Parts | Each is rare in vanilla; the wiki gives no rule for Disguise or Value and Parts |
