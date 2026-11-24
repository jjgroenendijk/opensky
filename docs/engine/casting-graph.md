---
type: Subsystem
title: Casting graph events
description: The behaviour graph events that start, ready, release, and fire a cast in each hand,
  which start event each kind of spell gets, and how a dual cast differs.
tags: [engine, magic, casting, animation, behavior]
---

# Casting graph events

A cast plays its clips through the actor's behaviour graph. The graph enters a casting state, and
an event that names the kind of cast picks the clips. The clips then raise the spell-fire event
that releases the spell ([casting cues](/engine/spellcasting.md#casting-cues)).

These facts come from a clean-room read of the game's behaviour. They describe what the game does;
they hold no code, offsets, or names from the program.

## Hand variables

- While a hand casts, the game sets `bWantCastRight` or `bWantCastLeft` to true. The graph raises
  `BeginCastRight` or `BeginCastLeft` itself when the value turns from false to true.
- When the hand stops casting, the graph raises `CastStop` itself.
- `iRightHandType` and `iLeftHandType` hold 9 for a spell and 8 for a staff. A staff plays the
  staff clips.

## The start event

The start event comes from the attack action of the hand: the right attack for the right hand, the
left attack for the left hand. The action picks the first idle in its tree whose conditions pass.
The idles for a spell need the hand to hold a spell. The event name starts with the hand's prefix:
`MRh_` for the right hand and `MLh_` for the left hand.

| Casting type | Delivery or keyword | Event after the prefix |
| --- | --- | --- |
| Fire and forget | Self | `SpellSelfStart` |
| Fire and forget | Aimed, Target Actor, or Target Location | `SpellAimedStart` |
| Fire and forget | Contact | none |
| Concentration | Self, with the `MagicTelekinesis` keyword | `SpellTelekinesisStart` |
| Concentration | Self, with the `MagicWard` keyword | `WardStart` |
| Concentration | Self, other spells | `SpellSelfConcentrationStart` |
| Concentration | Aimed, Target Actor, or Target Location | `SpellAimedConcentrationStart` |
| Constant effect | any | none |

The telekinesis keyword is checked before the ward keyword. The tree has two more branches before
these: one for an actor in bleed-out, and one for ritual spells (`RitualSpellStart` and
`RitualSpellAimConcentrationStart`). [WARNING] What makes a spell a ritual spell is not known.

## A fire-and-forget cast

The right hand of an aimed spell, in order:

1. `bWantCastRight` turns true, and the right attack action raises `MRh_SpellAimedStart`.
2. The graph plays the charge clips and loops until the charge is full.
3. When the charge is full, the right ready action raises `MRh_SpellReady_Event`.
4. When the button is let go, the right release action raises `MRh_SpellRelease_Event`.
5. The release clip raises `MRh_SpellFire_Event` 0.17 seconds in. The spell leaves on this event.
   A self spell's release fires at 0.37 seconds, and a staff's at 0.34 seconds.
6. At the end of the clip the graph raises `MRh_Equipped_Event`.

## A concentration cast

1. The start event is raised, as above.
2. The charge clip waits for `MRh_SpellRelease_Event`, from the right release action. The action
   most likely fires when the charge finishes.
3. The graph enters its loop. Entering the loop raises `MRh_SpellFire_Event`, and the effect starts.
4. The cast stops when `bWantCastRight` turns false, or on the right interrupt action
   (`MRh_Equipped_Event`). The graph then raises `CastStop`.

[WARNING] The read is unsure about the order of steps 2 and 4.

## A dual cast

A dual cast starts from the left attack action. Its branch is checked first, with the condition
that the actor is dual casting. The events have the prefix `DualMagic_`:

- `DualMagic_SpellAimedStart` and `DualMagic_SpellSelfStart`
- `DualMagic_SpellAimedConcentrationStart` and `DualMagic_SpellSelfConcentrationStart`
- `DualMagic_WardStart`

There is no dual telekinesis event. After the start, the ready and release events use the left
prefix (`MLh_SpellReady_Event`, `MLh_SpellRelease_Event`), and the clips raise
`MLh_SpellFire_Event`. The dual concentration clip raises it 0.17 seconds in.

## NPCs

NPCs use the same trees and the same events. [WARNING] The read did not confirm whether a staff or
a scroll uses other idles; most likely they use the same ones.
