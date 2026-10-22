---
type: Engine
title: Sandbox procedure
description: How a sandboxing actor picks and times its activities and meals from the game
  settings, and where this differs from the game.
tags: [engine, ai]
---

# Sandbox procedure

A sandbox procedure does one activity after another inside its package's place
([package schedules](/engine/package-schedules.md)). Source: the Creation Kit wiki page
<https://ck.uesp.net/wiki/Sandbox_(Procedure)>, and the game settings, read from the install.
All times are in game hours.

Each activity lasts `fSandboxDurationBase` (0.2) times the multiplier of its kind, scaled by
the procedure's Energy input (0 to 100):

```text
base     = fSandboxDurationBase * fSandboxDurationMult<Kind>
energy   = base * (1 + Energy * fSandboxEnergyMult * fSandboxEnergyMult<Kind>)
duration = random between energy * (1 - fSandboxDurationRangeMult)
                      and energy * (1 + fSandboxDurationRangeMult)
```

The kinds are Furniture, IdleMarker, EatSitting, EatStanding, Sitting, Sleeping, and
Wandering. Example: an idle marker with Energy 50 lasts 0.2 x 1.5 x (1 + 50 x 0.05 x -0.05)
= 0.26 game hours, about 47 real seconds at timescale 20.

- An actor inside the place starts at once. Inside means within the radius plus
  `fSandBoxRadiusHysteresis`, and between `fSandboxCylinderBottom` below and
  `fSandboxCylinderTop` above the centre. An actor outside walks in first.
- After a walk, the actor stands for a Wandering activity. When the idle runtime gave it an
  idle marker, it uses the marker for an IdleMarker activity instead.
- When an activity ends, the actor leaves its marker and walks to a new random point. The
  idle runtime does not give it the same marker, or one closer than
  `fSandBoxInterMarkerMinDist` to it, until it has done one Wandering activity.
- When the Allow Eating input is true, the actor eats three meals a day. Each meal starts at a
  random time between `fSandboxBreakfastMin` and `fSandboxBreakfastMax` (then Lunch, then
  Dinner), and lasts between `fSandboxMealDurationMin` and `fSandboxMealDurationMax`. The
  times are rolled once per game day. A meal that starts cuts the current activity short.
  Inside a meal, each activity is EatStanding, which asks for the eat loop.
- When the Allow Idle Markers input is false, the idle runtime gives the actor no marker.

The wiki lists twelve parameters. The procedure in the vanilla `Sandbox` template (`PACK`
named `Sandbox` in `Skyrim.esm`) has ten, read from its `PKC2` indexes and `BNAM` names on
the install: Location, Allow Eating, Allow Sleeping, Allow Conversation, Allow Idle Markers,
Allow Sitting, Allow Wandering, Prefered Path Only?, Energy (default 50), and Allow Special
Furniture. There is no Allow Furniture or Min Wander Distance. OpenSky reads Allow Eating
(position 1), Allow Idle Markers (4), and Energy (8).

`Skyrim.esm` holds only 14 of the settings: the duration base, the cylinder bottom, the
radius hysteresis, the lunch, dinner, and meal-length bounds, and the duration multipliers
and energy multiplier of furniture, idle markers, and eating. The others, such as
`fSandboxBreakfastMin`, `fSandboxDurationRangeMult`, and `fSandboxEnergyMult`, live only in
the game's executable. OpenSky uses the defaults from the Creation Kit wiki table
<https://ck.uesp.net/wiki/Category:Settings>, and a plugin that adds one overrides it.

The wiki's procedure page also lists meal and sleep times as `iSandbox...` settings, such as
`iSandboxLunchMin` (11) and `iSandboxLunchMax` (14), each with its own page
(<https://ck.uesp.net/wiki/ISandboxLunchMin>). `Skyrim.esm` holds no setting with these
names, and the settings table has the `fSandbox...` names with other values (lunch 11.5 to
12.5). OpenSky reads only the `fSandbox...` names.

Where OpenSky differs from the game:

- The game picks each activity from a weighted list of nearby objects. OpenSky only has idle
  markers and wandering, so the actor always takes a free marker when one is in the place.
- Furniture, sitting, sleeping, conversations, and special furniture are not used yet. Their
  duration settings are read, so the formula covers them.
- That the durations are game hours is an inference: the wiki gives hours only for meals and
  sleep. With game hours, a sandboxing actor stays at a marker for about a minute of real
  time, as in the game.
