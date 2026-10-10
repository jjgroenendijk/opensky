---
type: Subsystem
title: Visual effects
description: How OpenSky attaches effect art and effect-shader membranes to actors and points,
  and the approximations it makes.
tags: [rendering, magic, effects]
---

# Visual effects

A visual effect is what a spell, a race ability, or an explosion shows on an actor or at a
point. It has up to two parts:

- **Art**: a model from an `ARTO` (or an `ADDN`), drawn at the anchor.
- **Membrane**: an `EFSH` effect shader drawn as a glow over the actor's own meshes.

The records are in [visual effect records](/formats/visual-effects.md),
[effect shaders](/formats/effect-shaders.md), and [art objects](/formats/art-objects.md).

## Where effects come from

| Source | What attaches | How long |
| --- | --- | --- |
| A spell hit | The `MGEF` hit shader and hit effect art, on each target | The effect duration; for an instant spell, the shader's settle time or 2 s for art |
| A race ability | The same links of each `RACE SPLO` ability, on each resident actor of the race | While the actor is resident |
| An explosion | The `EXPL` model at the blast point | 2 s |
| An impact | The `IPCT` model at the contact point ([impacts and decals](/rendering/decals.md)) | 2 s |
| The Effects panel | Any `RFCT`, `EFSH`, `ADDN`, or `ARTO`, on the player or the nearest actor | Until cleared |

An `RFCT` is resolved to its `ARTO` model and its `EFSH` membrane. A lasting effect that is
already on the same anchor is not attached twice, so a reload does not stack race glows.
At most 32 effects live at once; the oldest timed one goes first. This is OpenSky's limit.

## Membrane

The membrane is an extra pass over the target's meshes after the opaque and alpha-tested
passes. It blends additively (one plus one) and does not write depth, with a small depth bias
so it wins over the surface below it. Its color is:

```text
fill + edge * (1 - facing) ^ falloff
```

`facing` is how directly the surface faces the camera, so the edge color shows at the
silhouette. The colors are the `EFSH` fill color key 1 and edge color, converted from sRGB to
linear, and scaled by the fill and edge alpha curves.

Each alpha curve fades in, holds at the full ratio, then fades out to the persistent ratio,
with an optional sine pulse. A shader with the no-membrane flag (0x01) or without a fill color
draws no membrane.

## Approximations

- The membrane and particle textures of the `EFSH` are not sampled. The membrane is a flat
  color with a rim term.
- The fill color has three keys in the record. OpenSky uses key 1 only.
- The NIF particle systems inside an effect model run while the effect lives, and move
  with its anchor. `EFSH` particles are not drawn.
- Art and membranes follow the actor's feet and facing, not a named bone. The `RFCT` node
  index is not used.
- An actor's membrane covers every mesh drawn for that actor, including worn armor.

## Checking it in the app

`World > Effects > Visual Effects` holds a record picker (`VisualEffectNameControl`) with the
record's details, buttons to attach it to the player or the nearest actor, a clear button, and
the live effects (`VisualEffectStatsLabel`).
