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
place. A reference held in a container follows the holder, up to 8 holders deep. `QSTA`
conditions are not evaluated yet.

## Local map

An exterior local map shows the 5 by 5 loaded cells around the player from above. An
interior shows every floor; the game cuts the view above the player's floor. Fog is an 8 by
8 grid per cell, one bit per square, kept in the `localMapFog` component on the player.

## Fast travel

Fast travel is refused, in this order, for combat, hostiles near, overencumbered, in the
air, an alarm, a location that forbids it, a script block (`Game.EnableFastTravel(false)`),
and an undiscovered target. The message is the matching `sNoFastTravel*` GMST string.

The trip moves the clock by the walk time: distance divided by the walk speed, times the
`TimeScale` default of 20. UESP "Skyrim:Time" says travel time depends on distance and
`TimeScale`; the exact formula is not documented, so this is an approximation. A travel
autosave follows when the player's setting asks for one.
