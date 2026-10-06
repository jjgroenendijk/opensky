---
type: Subsystem
title: World map, local map, and fast travel
description: Map marker discovery, the world map camera, quest targets, the local map fog,
  and how fast travel decides and moves.
tags: [engine, ui, menu, map]
---

# World map, local map, and fast travel

## Map markers

Map markers are `REFR` records with marker data (`XMRK`, `FNAM`, `FULL`, `TNAM`) in a
worldspace's persistent cell ([placed references](/formats/placed-references.md)). Each
marker keeps a `mapMarker` world-state component with three flags: visible, discovered,
and can travel to. Without a component the `FNAM` flags apply.

| GMST | Value in Skyrim.esm | Use |
| --- | --- | --- |
| `iMapMarkerRevealDistance` | 1000 | Closer than this discovers a marker |
| `iMapMarkerVisibleDistance` | 12500 | Closer than this shows it on the compass |
| `iXPRewardDiscoverMapMarker` | 10 | Character experience for a discovery |

Discovery runs each time the player has moved 128 units. A discovered marker is visible and
a travel target, and the HUD names it. `ObjectReference.AddToMap` shows a marker and makes
it a travel target only when asked.

## World map

The camera starts above the player and looks down at the worldspace's `MNAM` initial
pitch. It pans inside the map bounds from the `MNAM` north-west and south-east cells, and
zooms between the `MNAM` camera heights. Missing values fall back to 50000, 80000, and 50
degrees, the Tamriel values. The view is the live world drawn from the map camera; the
game's own map uses a separate LOD render.

The map selects the visible marker nearest its center, like the game's cursor.

## Quest targets

The targets come from the displayed, unfinished objectives of the quest selected in the
journal. Each objective `QSTA` target names an alias; the alias's reference gives the
place. A reference held in a container follows the holder, up to 8 holders deep.

Each target's conditions (the `CTDA` records after `QSTA`) must pass, or the target is
hidden. They run with the target's reference as the subject, the player as the Target
run-on, and the objective's quest as the alias quest. The subject is the target because the
most common check in `Skyrim.esm` is `GetDead` on the subject, on 155 targets. An example
with two targets is `MQ105Ustengrav` objective 20: one target needs `GetStage MQ105 < 10`
and the other `GetStage MQ105 >= 10`, so only one shows at a time.

## Local map

An exterior local map shows the 5 by 5 loaded cells around the player from above. An
interior shows every floor; the game cuts the view above the player's floor. Fog is an 8 by
8 grid per cell, one bit per square, kept in the `localMapFog` component on the player.

## Fast travel

Fast travel is refused for a script block (`Game.EnableFastTravel(false)`), an
undiscovered target, a location that forbids it, combat, hostiles near, an alarm, being in
the air, and being overencumbered, checked in that order. Overencumbered means the carried
weight is above the `CarryWeight` actor value. An alarm means guards pursue the player for
a crime. The message is the matching `sNoFastTravel*` GMST string.

The trip moves the clock by the walk time:

```text
game seconds = distance / (walk speed * fFastTravelSpeedMult) * TimeScale
```

The distance is the straight line in game units. The walk speed is the `NPC_Default_MT`
forward walk, 80.1 units per second. `fFastTravelSpeedMult` is 1 and `TimeScale` is 20 by
default. A travel autosave follows when the player's setting asks for one.

The formula was fitted to the Elder Scrolls wiki table "Fast Travel (Skyrim)", which lists
game hours between towns, measured in light armor and rounded to half hours.
`FastTravelTimeRealDataTests` (run with `make test-real`) measures the marker distances on
the install. A city without a marker of its own name is timed from its stables, and
Solitude is left out because nothing there sits beside its gate. The best-fit speed over the
36 measured routes is 80.7 units per second, within 1% of 80.1. With 80.1, the mean ratio
of OpenSky time to the table is 1.00; the test allows 5% for the mean and 20% for each
route. The worst route is Riverwood to Whiterun, 3 hours in the table and 2.4 in OpenSky. Results
are in
`.logs/fast-travel-time/routes.tsv`. For example, Riverwood to Winterhold is 171746 units:
the table says 12 hours, and OpenSky gives 11.9.
