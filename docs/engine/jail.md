---
type: Subsystem
title: Jail
description: How a jail sentence runs in OpenSky - the cell, the belongings chest, the jail
  outfit, serving the time, skill loss, and escape.
tags: [engine, crime, factions]
---

# Jail

A guard's arrest can end in jail ([guards and arrest](/engine/guard-response.md)). This page
covers what happens from the jail door to release or escape.

Sources: the Creation Kit wiki pages "Creating a Custom Crime Faction",
"SendPlayerToJail - Faction", "ServeTime - Game", "Escape Jail", and "OnStoryServedTime - Quest",
and UESP "Skyrim:Crime", Going to Jail.

## The faction's jail links

A crime faction names its jail in five `FACT` fields ([factions](/formats/factions.md)):

| Field | Creation Kit name | Use |
| --- | --- | --- |
| `JAIL` | Exterior Jail Marker | A PrisonMarker door outside the jail. Its `XTEL` leads to the PrisonMarker inside the cell |
| `WAIT` | Follower Wait Marker | Where followers wait. Not read yet |
| `STOL` | Stolen Goods Container | The evidence chest for stolen goods |
| `PLCN` | Player Inventory Container | The chest for the player's other belongings |
| `JOUT` | Jail Outfit | What the player wears in the cell. Vanilla factions use `BeggarOutfit` |

The tutorial: the two PrisonMarkers "must link to eachother in their teleport data". The outside
one is "where the player ends up after paying the fine or being released from jail".

## Going in

`SendPlayerToJail` runs these steps:

1. Stolen goods go to the `STOL` chest, as for a paid fine.
2. The bounty is cleared, so guards in the jail do not arrest the player again.
3. The player goes through the `JAIL` door, so they arrive at the PrisonMarker in the cell.
4. Everything else the player carries goes to the `PLCN` chest, except one lockpick. UESP: "You
   are able to keep one lockpick, which you can use to try to escape".
5. The `JOUT` pieces are given and worn.

A faction with no `JAIL` door, or a door that cannot be entered, falls back to serving the
sentence at once: the clock moves forward and the player stands on the marker if it is loaded.

The stay begins in the first cell the player stands in after the arrest. That is the jail cell.

## Serving the sentence

UESP: "To serve your sentence, sleep in a cell bed. You'll awaken when your time has been served."
Activating any bed during a stay asks `sServeSentenceQuestion`, "Do you want to serve your time in
jail?", with the buttons `sYesText` and `sNoText`. UESP "Skyrim:Blindsighted" quotes the question as
"Serve your time in jail?". Yes serves the sentence; `Game.ServeTime` serves it without asking.
Serving:

- moves the game clock forward by the sentence;
- clears skill progress (below);
- takes the `JOUT` pieces back and returns everything in the `PLCN` chest;
- sends the player out through the PrisonMarker in the cell, to the `JAIL` marker;
- adds the days to "Days Jailed", and fires `STIJ` (served time) with the faction, the bounty, and
  the days.

"Times Jailed" counts at the arrest, and the `JAIL` story event fires there.

## Skill loss

UESP: "You will lose progress towards one or more skill level advancements; the longer your
sentence, the more skills are affected ... if you serve seven days, your skill advancement will be
cleared for every skill."

No source gives the exact rule. OpenSky clears the progress of `ceil(18 x days / maximum days)`
skills: 3 for one day, 18 for seven. It picks the skills nearest their next level first, so the
loss is felt. Both the count and the order are OpenSky's reading.

`fCrimeGoldSkillPenaltyMult` (0.1) is in the settings list, but no source says what it scales, so
OpenSky does not read it.

## Escape

Leaving the jail cell by any way but serving is an escape. UESP: "If you do escape, your bounty
will remain." So the bounty cleared at the arrest is owed again, in its violent and non-violent
halves. The escape is a crime of its own: it adds the faction's escape price (`CRVA` escape, or
`iCrimeGoldEscape` 100) to the violent half, because the Creation Kit's Crime page lists escape
under "Major Crimes", and the ledger counts it. The escape
fires `ESJA` with the player as `R1` and the faction as `F1`, and counts "Jail Escapes". The
belongings stay in the `PLCN` chest for the player to find.

## Not done yet

- The stay lives in the session, not in a save. A save made in the cell loads as a free player
  whose belongings are still in the chest.
- `SendPlayerToJail`'s two parameters are not read.
- Quest items are moved to the chest like any other item. The game hides them instead.
- Followers do not go to the `WAIT` marker.
- Cidhna Mine's pickaxe-and-ore way of serving time is a quest script, not part of this.
