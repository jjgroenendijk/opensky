---
type: Subsystem
title: AI spell use
description: How an NPC that owns spells casts them in a fight - the same cast path as the player,
  where its spells come from including leveled spell lists, which spells become options, and what
  is simplified on purpose.
tags: [engine, magic, combat, combat-ai, npc, spells]
---

# AI spell use

An NPC that owns spells casts them in a fight. The decision of when to cast is on the
[combat behavior](/engine/combat-behavior.md) page. This page covers what stands behind it.

## The same path as the player

A fighting actor's spell is readied, begun, charged, and released through the same four calls the
panel's Cast button makes for the player ([spellcasting](/engine/spellcasting.md)). So casts in
progress are keyed by the actor and the hand, not the hand alone: two actors charging at once are two
casts.

An NPC always casts with its right hand. Vanilla NPCs cast from either hand and dual-cast. One hand
is a simplification.

## Where an NPC's spells come from

The spells are read from records, beside the spellbook, as inventory baselines sit beside the
inventory:

| Source | Field | Inherited through |
| --- | --- | --- |
| The `NPC_` | `SPLO` list | `ACBS` "Use Spell List": a record passes its list up only while that bit is set |
| The actor's `RACE` | `SPLO` list | The traits template, because the race an actor is comes from its traits |

An entry may name a leveled spell list (`LVSP`), and for vanilla casters the useful ones do. In
`Skyrim.esm`, `LvlBanditWizard` has seven `SPLO` entries. Every one that is a `SPEL` is a self buff
or a heal: Ironflesh, a ward, two heals, a racial ability, and a Breton power. Its attack spells are
behind two `LVSP` records, `LSpellBandit03FireFrostShock` and `LSpellBandit05FireFrostShock`, each
with three choices at level 1. Without expanding those, a vanilla caster knows nothing to throw. The
entry chosen is the highest level, then the first among ties: the same rule the template chain uses
for an `LVLN` and the outfit chain for an `LVLI`.

The list is added to the actor's spellbook the first time the combat loop asks what that actor can
cast, and its abilities are applied in the same pass. This is done late, not at cell build: a cell of
forty townsfolk who never fight would otherwise write forty spellbooks into the save, repeating what
their records say. Doing it twice changes nothing.

## Which spells become options

A known spell becomes a combat option only if it passes four checks:

| Check | Refuses |
| --- | --- |
| The spell type is spell | An ability, which is carried, and a power, a once-a-day resource this layer has no rule for |
| The delivery is not self | A self buff or heal, which is not something to throw at someone |
| Some effect entry is hostile | A heal or buff cast at an enemy |
| OpenSky runs the delivery, and the `ETYP` takes a hand | A cast that would only be counted as missing, or one with no hand to cast from |

An option carries the cost, the range (`SPIT`'s, or the session's aimed limit for a record that sets
none), the charge time, and whether it is held. The machine reads these and never reads a record.

In the install, `LvlBanditWizard`'s nine known spells give two options: Ice Spike at 48 magicka and
Ice Storm at 144, both aimed and reaching 4,000 units.

## What a released cast does

The same as the player's. An aimed fire-and-forget spell fires its `PROJ`
([spell delivery](/engine/spell-delivery.md)). A target actor spell applies to what the caster's aim
ray reaches. A held spell is held for 1.5 s and applies once a second. Only the ray differs: an NPC's
spell leaves the NPC's own eye, aimed at the middle of the player's capsule.

A cast in progress is dropped whenever the fight takes it away: a stagger, fleeing, a lost target, a
stopped fight, death, or the panel switch turned off. A held cast whose `SPIT` minimum duration has
not passed is dropped too. The player's release waits for the minimum because their button is still
held. An NPC has no button.

## Simplified on purpose

- Combat style (`CSTY`) is not decoded. Vanilla tunes when a caster prefers magic, at what range, and
  with what magicka limits through `CSTY` and game settings. OpenSky uses one probability and one
  choice rule ([combat behavior settings](/engine/combat-behavior.md#settings)). Decoding the style
  is the next step if the simple rule looks wrong in play.
- The strongest affordable spell wins. Cost stands in for strength, because no record ranks a
  caster's spells.
- No shouts, summons, reanimation, or healing itself mid-fight. An NPC only casts a hostile spell at
  its target. The buffs and heals in its list are known and never chosen.

## Controls

World > Combat & Physics > Combat Loop has the AI casting switch. The readout's "AI casting:" line
shows whether it is on, and each fighter's line shows "N casts (M castable)".
