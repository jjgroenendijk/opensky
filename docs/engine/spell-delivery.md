---
type: Subsystem
title: Spell delivery
description: Spells that leave the caster - which deliveries run, spell projectiles through the
  arrow pipeline, which actors a landed spell reaches, the EFIT area unit, resistance scaling on a
  hostile hit, and what a hit tells the combat loop.
tags: [engine, magic, spells, projectiles, resistances, combat]
---

# Spell delivery

A spell that leaves the caster is delivered to something else. Casting itself is on the
[spellcasting](/engine/spellcasting.md) page.

## Which deliveries run

The delivery values are the record's own, from `MGEF` `DATA` and `SPIT`: 0 Self, 1 Touch, 2 Aimed, 3
Target Actor, 4 Target Location (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>). UESP's
Magic Overview describes the shapes:

> Spells that don't target the one using them vary in range: some only work on touch, several are
> fired as projectiles, some are maintained as a short-ranged spray, and a few (primarily Master
> level spells) affect everything within a certain distance of the caster.
> (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>)

| Delivery | Fire and forget | Concentration |
| --- | --- | --- |
| Self | Applies to the caster | Applies to the caster once a second |
| Aimed | Fires the `MGEF`'s `PROJ` | Applies to whatever the aim ray reaches, once a second |
| Target Actor | Applies to the aimed actor, within `SPIT` range | Refused |
| Touch | Refused | Refused |
| Target Location | Refused | Refused |

A refusal is the `deliveryUnsupported` failure, with a sentence and a count. The reasons differ:

- Touch needs melee reach and the contact frame the animation graph owns. Treating it as a
  zero-range aimed cast would land a "touch" spell at the far end of a room.
- Target Location places an effect on the ground, which vanilla does with an `EXPL` or a rune.
  Explosions are not run yet, so the effect has nowhere to live.
- Holding a beam on a named actor needs targeting OpenSky does not do.

The install has 1,452 `SPEL` records: 733 self, 451 aimed, 155 touch, 74 target location, and 39
target actor. So 1,218 of them, 84%, use a delivery OpenSky runs.

What a delivery carries is fixed once, when the spell is cast: the spell, its plugin, the caster, the
whole effect list, whether any entry is hostile, the `SPEL` "Ignore Resistance" flag, and the `PROJ`
its `MGEF` names. A bow's damage follows the same rule. A spell in the air must apply the spell that
was cast, not whatever the caster has readied when it lands.

## Spell projectiles

There is one projectile pipeline. An aimed fire-and-forget cast fires its `PROJ` through the same
runtime an arrow flies through, with the same fixed step, integrator, impact query, and range and
lifetime limits. The arrow-only parts (spending ammunition, sticking in the surface, the
draw-scaled speed, and the upward tilt) apply only to an arrow
([projectiles](/engine/projectiles.md)).

The `PROJ` is found by the form ID the `MGEF` holds, not through an `AMMO`. A spell whose `MGEF`
names no `PROJ`, whose `PROJ` the load order lacks, or whose `PROJ` is hitscan or has no speed
launches nothing. That is a counted refusal, not a projectile standing still in the caster's face.

Aimed concentration, the flamethrower shape, fires nothing. It uses the aim ray and applies to
whatever the ray reaches, once at the start and once per second held. The ray is taken again on
every application, so moving the beam off a target stops applying to it while the cast keeps running
and costing.

A spell projectile is not drawn yet: no model, no muzzle flash, and no impact art. The Archery
panel's trace shows its path. There is no aim assist. Vanilla nudges a cast toward a target, and
OpenSky aims exactly where the camera points, as it does for arrows.

## What a landed spell reaches

The struck actor is the direct target and gets every entry. Then every actor inside the widest area
the spell carries is a bystander, and gets only the entries whose own area reaches it. Vanilla
`Fireball` is built for this: an area damage entry beside a point stagger entry, so the blast damages
everything nearby and staggers only what it hit.

- The caster is never caught by its own spell.
- Bystanders are ordered by distance and then by key, so the order is always the same.
- Distance is measured to the actor's capsule, not its feet, so a blast at head height catches
  someone standing beside it.
- A projectile that hit geometry still applies its area entries to whoever stands by the wall. A
  spell with only point effects reaches nobody there.

`EFIT` area is in feet. This was measured: the game setting table names the unit outright
(`sMagicEffectItemFeet`), and vanilla `Fireball` has an `EFIT` area of 15, while UESP describes it
as "a fiery explosion for 40 points of damage in a 15 foot radius"
(<https://en.uesp.net/wiki/Skyrim:Fireball>).

How many world units make a foot is not settled by any source found. OpenSky uses 128/6 units per
foot, from its own 128-unit capsule height for an adult human. It is a setting, not a constant, so it
can be corrected without changing the rule. Settling it needs the running game: cast `Fireball`
between two actors a known distance apart, and find where the second stops taking damage.

Vanilla detonates the `PROJ`'s explosion. OpenSky decodes the explosion link but does not run it, so
an area spell reaches actors through its `EFIT` area.

## Resistances on a hit

Only hostile effects are scaled. UESP states the rule for damage: "Magic Resistance decreases the
damage of any offensive spell by the displayed percentage"
(<https://en.uesp.net/wiki/Skyrim:Magic_Overview>). The `MGEF` Hostile flag is the record's word for
"offensive". A restore or a fortify arrives unscaled, so a healing spell is not resisted.

The multiplier is the one on the [actor values](/engine/actor-values.md#resistances) page: Resist
Magic first, then the `MGEF`'s own resistance value, multiplied, with the 85% cap for the player
only. A weakness is the same formula with a negative resistance: -30 points multiplies damage by 1.3.
The `SPEL` flag xEdit calls "Ignore Resistance" skips the whole step.

Every scaled entry records the effect, the target, the resistance value, the base magnitude, and the
multiplier. A moving health bar does not prove the multiplier was the documented one, so the
Spellcasting panel prints each one.

Wards, spell absorption, and reflect are not implemented. UESP says "Spell Absorption is calculated
before Magic Resistance", so the order is known. The `SPEL` "Disallow Absorb/Reflect" flag is decoded
and not read.

## What a hit tells the fight

A landed spell reports to the [combat loop](/engine/combat.md) as an arrow does: the target is
angered, put in the fight, and staggered. Death is unchanged: the effect moves health, and the death
component answers when it reaches zero.

Only a hostile spell angers. Every arrow does. Healing a follower at range must not start a fight with
them. A projectile that ended in the air angers nobody, because it reached nobody.

A spell hit also raises `OnHit` on the target's scripts, with the `PROJ` named. `akSource` is `None`,
not the spell: the event carries a form ID, and a cast spell is identified by a load-order key that
a raw form ID cannot represent.
