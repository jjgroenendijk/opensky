---
type: Subsystem
title: Detection events
description: The sound events the game keeps per actor for detection - what makes one, its
  level, how long it lasts, and how an observer that sees nothing checks it.
tags: [engine, stealth, detection, npc, audio]
---

# Detection events

An observer that cannot see a target can still notice a sound the target made. The game keeps
one sound event per actor for this. The page belongs to [detection](/engine/detection.md),
which holds the formula.

Behaviour described from clean-room reads of the game program (1.6.1170), the last one on
2026-11-22.

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
| An explosion | The explosion record's sound level | The explosion; its owner |
| A projectile impact | The impact data's sound level | The impact point; the shooter |
| A flying projectile | The projectile record's sound level | The projectile; the shooter |
| Summoning a creature | Loud | The summon point; the caster |
| `ObjectReference.CreateDetectionEvent` | The level given | The reference; the owner given |

- A spell cast makes no event when the perk entry point Mod Spell Casting Sound Event gives 0.
- When exactly a flying projectile makes its event was not found.
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
- A positive result gives the detection value 0, at the event position.

## In OpenSky

OpenSky keeps the last sound event of each actor and drops it after 5 seconds. The player is
the only detection target, so only the player's events are checked.

| Action | Level |
| --- | --- |
| A spell cast | The casting sound level of the spell's first effect, for as long as the cast lasts |
| A landed projectile | The sound level of its impact data, or Normal without one |
| The explosion of a projectile | The explosion record's sound level, or Normal without one |
| A summon | Loud, at the place of the summon |
| `ObjectReference.CreateDetectionEvent` | The level given, at the reference |

An aggressive observer whose formula value is not positive checks the event:

- The event must be within 1,536 units, or 3,072 units for a very loud one.
- The sound-only formula runs with the event's level as the Action sound, at the distance to
  the event. A wall between the observer's eyes and the event multiplies the sound by
  `fSneakSoundLosMult`. When the place is in view, the fixed light level adds a sight term.
- On a positive result an unaware observer becomes suspicious, the event is the place it
  searches, and the target's [stealth points](/engine/detection.md#stealth-points) wait. The
  points wait once for one event. The observer stays suspicious for as long as the event lasts.

`openskycli game state actors` shows the player's live event in an actor's `detection` as
`soundEvent`, with its `level` and its `age` in seconds. `game debug detectionevent <level>`
makes an event of the player at the player's feet.

- [WARNING] A flying projectile makes no event, and the check of a target's projectiles within
  1,024 units is not built.
- [WARNING] An explosion that a spell or a script places without a projectile makes no event.
- [WARNING] An observer that is not aggressive does not check an event. In the game every
  observer does.
- [INFO] The pair's detection value stays negative after a heard event. The game sets it to 0.
