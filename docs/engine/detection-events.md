---
type: Subsystem
title: Detection events
description: The sound events the game keeps per actor for detection - what makes one, its
  level, how long it lasts, and how an observer that sees nothing checks it.
tags: [engine, stealth, detection, npc, audio]
---

# Detection events

An observer that cannot see a target can still notice a sound the target made. The game keeps
one sound event per actor for this. The page belongs to [detection](detection.md),
which holds the formula.

## The event

- Each actor keeps one last event: its sound level, its position, its time, and the reference
  that made it. A new event replaces the old one.
- An event older than `fDetectionEventExpireTime`, 5 seconds, is dropped.
- Only an actor with AI process data keeps an event.

## Sound levels

| Level in a record | Name | Value |
| --- | --- | --- |
| 0 | Loud | `iSoundLevelLoud`, 100 |
| 1 | Normal | `iSoundLevelNormal`, 50 |
| 2 | Silent | `iSoundLevelSilent`, 10 |
| 3 | Very loud | `iSoundLevelVeryLoud`, 200 |

## What makes an event

| Action | Level | Position, and whose event it is |
| --- | --- | --- |
| A spell cast | The casting sound level of the effect, most likely the costliest one | The caster |
| An explosion with an owner actor | The explosion record's sound level | The explosion; its owner |
| An explosion with damage above 0 that hits an actor | The explosion record's sound level | The hit actor; the shooter |
| A projectile impact | The sound level of the impact data for the hit surface's material | The impact point; the shooter |
| Summoning a creature | Loud | The summon point; the caster |
| `ObjectReference.CreateDetectionEvent` | The level given | The reference; the owner given |

- A spell cast makes no event when the perk entry point Mod Spell Casting Sound Event gives 0.
- A projectile impact makes one event. It makes none when the projectile has no impact data set,
  or the set has no impact data for the material it hit.
- An explosion makes its event when it is set up. A spell's or a projectile's explosion is owned
  by the caster or the shooter. An explosion a script places with `PlaceAtMe` has no owner, so
  it makes no event.
- An explosion with damage above 0 whose projectile hit an actor also tells that actor that the
  shooter attacked it.
- A flying projectile makes no event: not at launch, and not while it flies. Observers find it
  only through the projectile check below.

  [WARNING] The game's fire step was also seen to make an event from the weapon's sound level at
  the shooter, right after the weapon's `SNAM` or `XNAM` fire sound
  ([items](../formats/item-records.md#weap)). This may be the action sound below rather than an
  event; which one it is was not settled.
- These make no event: a weapon swing, a weapon hit, a drawn bow, a footstep, a jump, a door,
  and a trap other than through its explosion or projectile.

## The action sound

A second value feeds the Action part of the Sound term of the formula. It is not an event and
has no position of its own.

- A melee swing sets it to the weapon's sound level, or to the NPC's own sound level for an
  unarmed swing. The unarmed case is not confirmed.
- A shot from a bow or a crossbow sets it to the weapon's sound level.
- A spell cast sets it to the casting sound level.
- It lasts `fActorAlertSoundTimer`, 5 seconds.

## Who checks an event

Not every observer checks. An observer checks a target's event only when both of these hold:

1. Its reaction to the target is not Ally or Friend.
2. The observer is in combat, the target is in combat, or the target is the player and the
   observer would be hostile to the player.

The reaction comes from the relationship rank, then the faction reactions refine it:

| Rank | Reaction |
| --- | --- |
| 2 or more | Ally |
| 1 | Friend |
| 0 or -1 | Neutral |
| Below -1 | Enemy |

An observer would be hostile to the player when it would attack the player by its own Aggression
and reaction, or when it has an [aggro radius](aggro-radius.md) with a
Warn/Attack or Attack distance above 0 and its reaction to the player is Neutral or Enemy.

So a neutral guard never checks the player's sound while neither of them fights. The check of the
target's projectiles is skipped in one more case: the target is not the player and is not in
combat. What an observer does after it hears an event, beyond the stored place, was not found.

## How an observer checks an event

When the sight value is not positive, or the target is out of range, the observer checks the
target's last sound event:

- The event counts within 1,536 units for the player's sound and 512 units for another
  actor's. A very loud sound (level 200 or more) doubles the distance.
- A sound-only form of the formula runs. Its light level is fixed at 225 indoors and 75
  outdoors, and is used only when the event position is in view. Its range for a very loud
  event is 3,072 units.
- The observer then checks the target's projectiles within 1,024 units (player) or 512 units
  (another actor), at sound level 50.
- A positive result gives the detection value 0, and stores the event position as the place the
  target was heard.

An actor with an aggro radius has one more rule. When the player's event is less than 0.1 s old,
lies inside the larger of the actor's Warn/Attack and Attack distances, and the actor does not
already fight the player, the actor reacts at once, with no warning and no detection roll. It
starts combat when it [would attack](aggro-radius.md) the player. An actor
with Aggression 0 and Confidence 0 flees instead.

## In OpenSky

OpenSky keeps the last sound event of each actor and drops it after 5 seconds. An NPC's events
are checked only by an observer that tracks that NPC as a target.

| Action | Level |
| --- | --- |
| A spell cast | The casting sound level of the spell's first effect, for as long as the cast lasts |
| A landed projectile | The sound level of its impact data, or Normal without one |
| The explosion of a projectile | The explosion record's sound level, or Normal without one |
| An explosion of a spell or a script with an owner | The same, at the blast |
| A summon | Loud, at the place of the summon |
| `ObjectReference.CreateDetectionEvent` | The level given, at the reference |

An observer whose formula value is not positive checks the event when the rule in
[who checks an event](#who-checks-an-event) lets it. An observer in combat counts as fighting,
and an aggressive observer, one that is hostile or fighting, counts as one that would attack
the player.

- The event must be within 1,536 units, or 3,072 units for a very loud one.
- The sound-only formula runs with the event's level as the Action sound, at the distance to
  the event. A wall between the observer's eyes and the event multiplies the sound by
  `fSneakSoundLosMult`. When the place is in view, the fixed light level adds a sight term.
- On a positive result an unaware observer becomes suspicious, the event is the place it
  searches, the pair's value becomes 0, and the target's
  [stealth points](detection.md#stealth-points) wait. The points wait once for one
  event. The observer stays suspicious for as long as the event lasts.
- Without a heard event, the observer checks the nearest of the target's flying projectiles
  within 1,024 units the same way, as a Normal sound at the projectile. It skips the scan for a
  target that is neither the player nor in combat.

`openskycli game state actors` shows the player's live event in an actor's `detection` as
`soundEvent`, with its `level` and its `age` in seconds. `game debug detectionevent <level>`
makes an event of the player at the player's feet.

- [INFO] An explosion that hits an actor makes no second event at that actor, because each
  actor keeps only its last event.
- [INFO] The Frenzied reaction and the teammate cases of the reaction test are not built.
