---
type: File Format
title: Speed data
description: Layout of meshes\speeddatasinglefile.txt, the table that maps an actor's ground
  speed to the blend speed its behaviour graph plays, and how the speed sampler reads it.
tags: [animation, behavior]
---

# Speed data

`meshes\speeddatasinglefile.txt` holds, for each behaviour project, how fast the feet of a
blended walk or run move at each blend value. A graph's speed sampler modifier
(`BSSpeedSamplerModifier`) reads it. The modifier gets the actor's real ground speed (the goal)
and returns the blend value whose clips move the feet at that speed. Without the table, the feet
slide: at a body speed of 100 units per second the human walk blend plays feet at about 88.

Sources: a clean-room read of `SkyrimSE.exe`, 2026-11-07, for the lookup rules. The layout was
read from the file on the real install with a probe. No open spec describes this file. All
integers and floats are little-endian, 4 bytes.

## Layout

The file starts as text and ends as binary.

| Part | Content |
| --- | --- |
| Count line | The number of projects, in ASCII digits, ending in CR LF |
| Name lines | One per project, such as `DefaultMaleData\DefaultMale.spd`, each ending in CR LF |
| Project blocks | One per name line, in the same order, with no separator |

A project block:

| Field | Type |
| --- | --- |
| Version | int32, always 1 |
| State count | int32 |
| Per state: state key | int32 |
| Per state: direction count | int32 |
| Per direction: direction key | float |
| Per direction: pair count | int32 |
| Per pair: blend speed | float |
| Per pair: ground speed | float |

A pair stores the blend speed first. Pairs are sorted by ground speed.

The vanilla file has 49 projects. The human project, `DefaultMale`, has states 0 to 10 and 15
to 17. The horse project has state 60. OpenSky matches a project by its file name in lower case,
without folder or extension, so `defaultmale.hkx` finds `DefaultMale.spd`.

Example, `DefaultMale` state 0, direction 0, as (blend, ground):

```text
(0, 8.2) (48.5, 16.1) (67.5, 29.3) (76, 46.1) (80.5, 66.4) (82.5, 82.1)
(144, 102.1) (212.5, 164.4) (272, 232.1) (321, 300.9) (324.5, 306.4)
```

## Lookup

The modifier reads its state, direction, and goal from its bindings, then:

1. Picks the state's table. No table for the state: the output is the goal.
2. Picks the direction: the first key at or above the input. Above the last key, it wraps to
   the first table.
3. Finds the first pair whose ground speed is at or above the goal, and interpolates the blend
   speed from the pair before it. Before the first pair, it interpolates from (0, 0).
4. A goal above the last ground speed passes through unchanged.

Any lookup that fails outputs the goal. The output is usually bound to `SpeedSampled` (and
`HorseSpeedSampled` on the horse). The engine writes `Speed`, never `SpeedSampled`; there is no
playback-rate scaling on top. See [the locomotion graph](/engine/locomotion-graph.md).
