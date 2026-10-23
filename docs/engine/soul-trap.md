---
type: Subsystem
title: Soul trap
description: Which soul a dying actor has, which gem it fills, how a filled gem is stored,
  and Actor.TrapSoul.
tags: [engine, magic, soul-gems, enchanting]
---

# Soul trap

The Soul Trap archetype is a held effect with no actor value. The Creation Kit: "If the target
dies while this effect is active, fills a soul gem carried by the caster. If the caster dies,
the effect is dispelled without filling any soul gem"
(<https://ck.uesp.net/wiki/Magic_Effect>). Every death reaches the magic session once, from the
same place that raises `OnDying` and `OnDeath`. The session looks for a soul trap effect on the
dying actor and fills a gem for its caster.

## The soul

UESP "Skyrim:Souls" (<https://en.uesp.net/wiki/Skyrim:Souls>):

> All NPCs, Dremora, and ghosts have Black souls, which are as powerful as Grand souls but only
> fit in Black soul gems or The Black Star.

Any other creature's soul follows its level. The thresholds are game settings, the same numbers
as the UESP table:

| Soul | Charge | Level from | Setting |
| --- | --- | --- | --- |
| Petty | 250 | 1 | |
| Lesser | 500 | 4 | `iLesserSoulActorLevel` |
| Common | 1000 | 16 | `iCommonSoulActorLevel` |
| Greater | 2000 | 28 | `iGreaterSoulActorLevel` |
| Grand | 3000 | 38 | `iGrandSoulActorLevel` |

The Creation Kit says `GetIsCreature` always returns 0 and that the `ActorTypeNPC` keyword tells
an NPC apart (<https://ck.uesp.net/wiki/GetIsCreature>). OpenSky gives an actor a black soul when
its base record or its race carries `ActorTypeNPC`. On the install `NordRace` and `DremoraRace`
carry it and `WolfRace` does not, which matches UESP for those three. Ghosts were not checked.

## The gem

UESP "Skyrim:Soul Trap (effect)" (<https://en.uesp.net/wiki/Skyrim:Soul_Trap_(effect)>): "Souls
will always fill the smallest empty Soul Gem that can accommodate it." A black gem holds any soul,
and a black soul fits only in a black gem. When a white and a black gem are the same size, the
white one is used first, so a black gem is kept for a black soul. That tie rule is OpenSky's.

A filled gem is stored in one of two ways:

- The `SLGM` `NAM0` field names a filled record. UESP: "This is only used twice, once for an empty
  Grand and an empty Black Soul Gem" (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SLGM>).
  When the soul fills such a gem to its capacity, the empty gem is swapped for the filled record,
  so it stacks with the game's own filled gems.
- Any other gem keeps the soul on its own [copy](/engine/item-copies.md). UESP notes that the
  game's self-filled gems "do not stack properly", which is the same model.

The HUD shows `sSoulCaptured`, or `sSoulGemTooSmall` when no carried gem holds the soul.

Only the player's gems are filled. An NPC that soul-traps an actor fills nothing, because no NPC
uses soul gems.

## Papyrus

`bool TrapSoul(Actor akTarget)` runs the same fill for the calling actor
(<https://ck.uesp.net/wiki/TrapSoul_-_Actor>). It answers true only when a gem was filled.

## Where it shows
