---
type: Subsystem
title: Impacts and decals
description: How a footstep, a melee hit, or a projectile hit shows its impact model and
  leaves a decal, and the approximations OpenSky makes.
tags: [rendering, effects, combat, audio]
---

# Impacts and decals

An impact is what a contact shows: dust under a step, sparks off stone, blood spray from a
hit. A decal is the flat mark it can leave, such as a blood splat. Both come from the same
`IPCT` record that picks the impact sound ([footstep records](/formats/footstep.md)).

## Data flow

```text
footstep:   FSTP tag  -> IPDS -> IPCT for the ground material
melee hit:  WEAP INAM -> IPDS -> IPCT for the body material
projectile: PROJ / WEAP -> IPDS -> IPCT for the surface or body material
IPCT -> sound, MODL impact model, DNAM TXST + DODT decal
```

The material lookup follows the `MATT` `PNAM` parent chain ([material types](/formats/material-type.md)).
An actor's body material is its race's `RACE` `NAM4` impact material.

The impact model plays as a short effect at the contact point. It lives 2 s, like other
instant effect art ([visual effects](/rendering/visual-effects.md)), and its NIF particle
systems run while it lives. With `IPCT` `DATA` orientation 0 the model's up turns to the
surface normal; any other orientation follows the projectile, which a contact point does not
carry, so the model stands upright.

## Decals

The decal texture is the `TXST` `TX00` diffuse. Its size and color come from `DODT`. The
`IPCT` `DODT` wins over the `TXST` one. `IPCT` `DATA` flag bit 0 means "no decal".

| Step | What OpenSky does |
| --- | --- |
| Size | A random width and height inside the `DODT` minimum and maximum |
| Turn | A random angle around the surface normal |
| Texture | One cell of a 2 x 2 grid, unless `DODT` has the no-subtextures flag |
| Color | `DODT` color, divided by 255, times the texture |
| Place | 0.5 units off the surface, depth tested, no depth write |

The decals draw after the effect membranes, lit by the sun, ambient light, and shadow, with
fog. The random values come from a fixed seed, so a run places the same decals each time.

`[Display] uMaxDecals` limits the live decals; the oldest goes first. `[Decals] bDecals`
turns decals off ([graphics options](/engine/graphics-options.md)).

## Approximations

- OpenSky has no skin decals. A hit on an actor puts its decal on the ground under the actor.
- A decal is one flat quad. It does not wrap around a corner or follow uneven ground.
- The 2 x 2 subtexture grid is a reading of the vanilla blood textures, not a confirmed rule.
- Vanilla footstep `IPCT` records have a dust model and no decal, so steps leave no marks.

## Checking it in the app

`World > Effects > Impacts & Decals` holds the impact model switch (`ImpactModelsControl`), the decal
switch (`DecalsControl`), a button that shows the last impact again at the player's feet
(`ImpactRepeatControl`), a clear button (`DecalClearControl`), and the counts
(`ImpactStatsLabel`). The launcher's graphics page holds the impact effects switch, and the
decal options under Decals.
