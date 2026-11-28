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
that releases the spell ([casting cues](spellcasting.md#casting-cues)).

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
2. The charge clip waits for `MRh_SpellRelease_Event`, from the right release action. The caster
   sends that action when the charge finishes, without a ready action and without waiting for
   the button. A spell with no charge time, such as Flames, sends it in the same update as the
   start event.
3. The graph enters its loop. Entering the loop raises `MRh_SpellFire_Event`, and the effect starts.
4. The cast stops when `bWantCastRight` turns false, or on the right interrupt action
   (`MRh_Equipped_Event`). The graph then raises `CastStop`. Letting go of the button ends the cast
   this way; it sends no second release.

## A dual cast

A dual cast starts from the left attack action. Its branch is checked first, with the condition
that the actor is dual casting. The events have the prefix `DualMagic_`:

- `DualMagic_SpellAimedStart` and `DualMagic_SpellSelfStart`
- `DualMagic_SpellAimedConcentrationStart` and `DualMagic_SpellSelfConcentrationStart`
- `DualMagic_WardStart`

There is no dual telekinesis event. After the start, the ready and release events use the left
prefix (`MLh_SpellReady_Event`, `MLh_SpellRelease_Event`), and the clips raise
`MLh_SpellFire_Event`. The dual concentration clip raises it 0.17 seconds in.

The game holds back the first press while a dual cast is possible. That is when both hands hold
the same spell, neither hand casts yet, and a perk lets the actor dual cast the spell:

- The first press goes through once its button has been held for more than 0.05 seconds.
- A press of the other button inside that window starts one dual cast. No single start event is
  raised.
- A second press after the window cannot join. The first hand already casts alone, and the second
  hand starts its own single cast.
- A tap shorter than the window can start nothing.

A dual cast runs on the left caster only, and both buttons drive it. `ActionDualRelease` holds
no magic branch; it is only used for a staff bash.

## NPCs

NPCs use the same trees and the same events. [WARNING] The read did not confirm whether a staff or
a scroll uses other idles; most likely they use the same ones.

## In OpenSky

- A hand that begins a cast raises its start event one step later, so the graph has entered its
  casting state from the rising `bWantCast` first. A hand that becomes the lead of a dual cast
  raises the `DualMagic_` start event, and a single start still waiting is dropped. The player's
  single start waits while the other hand may still join, up to the 0.05 second window.
- A fire-and-forget hand raises its ready event when the charge is full, and its release event
  when the button is let go. The spell then waits for the spell-fire event
  ([casting cues](spellcasting.md#casting-cues)).
- A concentration hand raises its release event when the charge is full. A spell with no charge
  time, such as Flames, raises it right after its start event. The graph's loop then
  raises the spell-fire event that starts the spell.
- A dual cast raises the left hand's ready and release events, and either hand's spell-fire event
  releases it.
- An NPC's graph gets the same events, and its `bWantCastLeft` and `bWantCastRight` flags. An NPC's
  spell still leaves when its charge ends; its graph's spell-fire event is not read.
- A spell counts as a ward or telekinesis when any of its effects carries the keyword. Lesser
  Ward has an armour effect beside its ward effect, and only the ward effect carries `MagicWard`.
- The ritual spell and bleed-out branches are not used.
- The readout's casting cue line names the last graph event a cast raised.
