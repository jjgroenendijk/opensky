---
type: Tool
title: Reference sky and music
description: The sky, music, location, and map marker state the reference game's bridge
  reports, and the console line that moves the player to a map marker.
tags: [tool, reference, sky, music, map]
---

# Reference sky and music

The [reference game](/tools/reference-game.md)'s bridge reports these members in
`state.json`. `openskycli reference state` prints them.

While the player stands in the world, `state.json` also holds `sky` and `music`. They give
the game's own numbers, so a sky or music rule can be measured instead of judged from a
capture.

| Member | What it holds |
| --- | --- |
| `sky.sun` | `direction`, a unit vector from the sky's centre to the sun disc; `lightDirection`, the way the sunlight travels; the disc's `look` |
| `sky.masser`, `sky.secunda` | `direction`, whether the moon is `hidden`, and its `look`: colour, alpha, and the phase texture |
| `sky.clouds` | Each cloud layer: `hidden`, `alpha`, its `look`, and three value pairs (`layerWords`, `materialOffset`, `materialScale`) that may hold the scroll |
| `sky.windSpeed`, `sky.windAngle`, `sky.weatherPercent` | The wind and how far a weather change has come |
| `music.current`, `music.queue` | The playing music type by editor ID, its `status` (1 playing), its track index, and the types waiting under it |

Vectors use the game's axes: +Y is north and +Z is up. None of the cloud value pairs moved
over 5 seconds in clear weather (observed 2026-11-05), so the cloud scroll is not among them.
The scroll rule is on the [weather](/engine/weather.md#clouds) page.

`reference send 'marker <name>'` moves the player to the map marker whose name matches, in any
case, for example `marker Whiterun` or `marker Embershard Mine`. It finds markers the player has
not discovered too. To test a first visit again, send `tmm 0` first, which hides every
marker. After it, `state.json` holds `marker`: whether one was `found`, its `formID`, its
`TNAM` marker `type`, and its `flags`. About 30 moves in a row crashed the game once
(2026-11-06), so restart it between long series.

In the world, `state.json` also holds `location`: the player's location `formID`, its
`keywords`, such as `LocTypeTown`, and its parent. The game keeps no editor IDs for
locations, so `editorID` and `parent` are often empty.
