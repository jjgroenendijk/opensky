---
type: Subsystem
title: World sound effects and ambience
description: How use-key and door events play sound effects, and how the current cell's regions
  or acoustic space choose a looping ambience bed that is not tied to a position.
tags: [engine, audio, sfx, ambience]
---

# World sound effects and ambience

The world sound director connects the [sound records](/formats/sound.md) to
[interaction](/engine/interaction.md) and to cell streaming. It plays one-shot sounds when the
player uses things, and a looping ambience bed for the current cell. It does nothing until the
[world audio engine](/engine/audio.md) is turned on.

## Events

The director listens to three events from cell streaming:

```text
interaction          -> play the activation sound
interaction phase:
  motion started     -> start the object's loop sound
  closed             -> stop the loop, play the close sound
  cancelled          -> stop the loop
ambience context     -> change the ambience bed
```

Scripts listen to the same interaction event beside the director. Neither replaces the other.

## Activation sounds

A use-key event carries the target's sounds, resolved when the cell was built from the base
record's sound fields ([world records](/formats/world-records.md)). The director resolves the
activation sound. It follows `SNDR` `GNAM` to `SNCT` `PNAM` to find the vanilla menu category,
and plays the sound at the reference's position. Missing or broken category data falls back to
Effects.

## Door sounds

When the player opens a door that leads somewhere, a "motion started" event is sent. The door's
data is kept while the destination cell builds in the background. Then:

- The build succeeds: "closed" is sent just before the new scene replaces the old one.
- The build fails: "cancelled" is sent.

A rebuild from a world state change sends none of these, because the player did not move.

On "motion started", the director starts the loop sound as a looping sound at the door. It
remembers that source by the door reference. So "closed" and "cancelled" stop exactly that loop,
and not the ambience or other effects. "Closed" then plays the close sound once. This covers
`DOOR` `BNAM` and `ANAM`. The same event also accepts `CONT` `QNAM`, once containers animate.

## Choosing the ambience bed

Cell streaming sends an ambience context whenever it changes:

- an exterior center cell sends its `XCLR` regions;
- an interior sends its `XCAS` acoustic space and its cell FormID.

The director turns the context into a fixed, ordered list of `SNDR` or `SOUN` FormIDs:

- exterior: the `RDSA` entries of each region's sound area (`RDAT` type 7). When a sound area
  has the override flag (`RDAT` flags bit 0), only the overriding region with the highest
  `RDAT` priority is used;
- interior: the acoustic space's `SNAM`, plus the sound area of the region it borrows through
  its own `RDAT` ([acoustic space](/formats/acoustic-space.md)).

The new bed is compared with the old one, and only the changes stop or start sources. A scene
swap sends the context again, so an interior entered twice still refreshes.

## Region sounds

Each `RDSA` entry holds a sound, a set of weather flags, and a chance
([region records](/formats/weather.md#regn)). The sound's `SNDR` decides how the entry plays:

- `LNAM` asks for a loop or an envelope: the entry is a loop. It plays without a break while it
  may play. The stream rewinds at the end of the file instead of finishing.
- Any other `LNAM`, or none: the entry is a one-shot. Every 1 to 5 seconds the director rolls.
  It checks the one-shots in record order, and the first whose chance hits plays once.

An entry may play when the current weather is in its weather flags and its `SNDR` conditions
pass with the player as subject. No flags means all weather. Indoors there is no weather, so
every entry may play. Each roll checks the loops again, so a weather change starts or stops a
loop within a few seconds.

Example: the Helgen road region has a wind loop and a gust with chance 0.07. The wind plays the
whole time. The gust plays about once a minute, not as a second loop.

[WARNING] No open source gives Skyrim's roll interval or the override rule. The interval is
Morrowind's, from OpenMW's fallback settings (1.0 to 5.0 seconds). The override rule follows the
Creation Kit region editor, which shows "Override" and "Priority" for each area.

## Bed lifetime

The director keeps two things:

- The wanted bed: what the last context resolved to, playing or not. A new context is compared
  with it, and turning ambience on again starts it.
- The playing sources: the IDs of the loops and one-shots it started. So stopping the bed stops
  only these, and an activation sound keeps playing.

A context change and the ambience toggle take the same path: stop what plays, then start the
wanted bed if ambience is on and the engine runs. So turning ambience off stops the bed at once.
Turning it on starts the last bed without waiting for a cell change. A context that arrives while
ambience is off is kept, not lost. A loop whose file arrives after it was stopped does not start.

The readout comes from the live sources, not the wanted bed. Sources the engine already stopped
are removed first. So the readout never claims a bed plays when it does not.

## Sound resolution

Door, activator, and container sound fields store a FormID without a fixed record type. So the
resolver also follows the old `SOUN` marker to its `SNDR` (`SOUN` `SDSC`). Vanilla SSE has no
`SOUN` markers on these records: every one points at a `SNDR` directly. The step is kept because
xEdit allows it.

The resolved descriptor also gives the category. In Skyrim, the ambience categories are children
of `AudioCategorySFX`, so vanilla effects and ambience both use the Effects volume. The same
resolver handles Footsteps, Voice, and Music without fixed FormIDs.

A descriptor with several `ANAM` tracks plays one of them, picked at random each time.

## Ambience has no position

Each bed sound connects straight to the submix of its resolved category. It has no world
position, panning, or distance fade. So moving away from where the context started cannot fade
the bed. The submix applies the category volume, mute, and solo once for the whole bed.

Beds are outside the positional source budget and are not purged with cells. The director alone
stops them: on a context change, through the toggle, or with Stop ambience.

## Threading

The director runs on the main actor, like the rest of the audio engine. A sound file is read and
parsed on the shared play-time worker ([concurrency](/decisions/concurrency.md)). A sound whose
file has not arrived starts after the drain that brings it, so it can start a frame or more late.
A loop or ambience bed that was stopped in the meantime does not start. Streaming decode runs on
the engine's decode queue. Nothing from OpenSky runs on the audio render thread. The sound, weather,
and acoustic space stores are immutable after they are built.

## Controls

World > Audio > SFX & Ambience:

- SFX enabled (on by default).
- Ambience enabled (on by default).
- Stop ambience: stops the current bed. The next cell change starts it again.
- Readout: the last sound played, the last error, and the current bed's FormIDs, or "none".

Reset all on the Audio destination clears this section and the Output section. Nothing sounds
until World > Audio > Output > Enabled is on.

A manual check: turn on audio, walk through a Whiterun exterior cell (its regions have beds),
press F on a door (open sound), and enter an interior (a bed from `XCAS`). Turning off SFX must
mute the door sounds but not the bed.
