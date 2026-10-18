---
type: Subsystem
title: Papyrus event registrations
description: The event registrations a script makes on itself, line of sight and tracked
  stats, how OpenSky checks them each frame, and where it differs from the game.
tags: [engine, papyrus, events]
---

# Papyrus event registrations

Some events reach a script only after it asks for them. The registration belongs to the
script instance that called the native: a quest, an alias, a reference script, or an active
magic effect. Other scripts on the same form do not hear the event. Registrations of a
script that no longer runs are dropped. The natives exist on `Form`, `Alias`, and
`ActiveMagicEffect`, like the update timers ([timers](/engine/papyrus-timers.md)).

## Line of sight

`RegisterForLOS(akViewer, akTarget)` asks for `OnGainLOS(akViewer, akTarget)` and
`OnLostLOS(akViewer, akTarget)` each time the viewer starts or stops seeing the target.
`RegisterForSingleLOSGain` and `RegisterForSingleLOSLost` ask for one event, and then the
registration ends. `UnregisterForLOS` ends it early. Source: the Creation Kit wiki pages
"RegisterForLOS - Form" and "OnGainLOS - Form".

The script coordinator checks every registered pair once a frame:

- The player as viewer sees a target when the target is inside the camera's field of view
  and a trace from the camera to the target meets no static collision. The field of view
  comes from the projection matrix. The wiki says the game does three picks clipped to the
  camera; OpenSky does one.
- An NPC as viewer uses the detection system, as the wiki says. OpenSky's detection tracks
  only NPCs observing the player, so an NPC viewer with any other target never reports.
- A pair the check cannot answer keeps its last state and sends nothing.

Where the wiki is silent, OpenSky chooses:

- A full registration reports the state it starts in: the first check sends `OnGainLOS` or
  `OnLostLOS`.
- A single registration whose state already holds fires on the first check.
- Registrations are not saved; the game saves them.
- The game throttles the checks, about one pick a frame. OpenSky checks every pair every
  frame.

## Tracked stats

`RegisterForTrackedStatsEvent()` asks for `OnTrackedStatsEvent(asStat, aiStatValue)` each
time a misc stat changes, with the stat's name and its new value. The stats are the misc
stats the journal shows; `Game.IncrementStat`, quests, crime, crafting, and other systems
raise them. The coordinator reads the world-state journal once a frame, so every change since
the last frame is reported, in name order. A loaded game is not reported as changes.
Registrations are not saved.

The wiki notes that some tracked stats do not send the event in the game. Which ones is not
documented, so OpenSky sends it for all of them.

## Sleep

`RegisterForSleep()` asks for `OnSleepStart(afSleepStartTime, afDesiredSleepEndTime)` when the
player sleeps in a bed, and `OnSleepStop(abInterrupted)` when the player wakes (Creation Kit
wiki "OnSleepStart - Form", <https://ck.uesp.net/wiki/OnSleepStart_-_Form>). The times are in
game days passed. OpenSky passes the hours at once, so both events queue together and sleep
is never interrupted. Waiting sends neither event. Registrations are not saved.
