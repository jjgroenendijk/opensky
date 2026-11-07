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

`[Display] uMaxDecals` limits the live decals; the oldest goes first. `[Display]
iMaxDecalsPerFrame` limits the decals placed in one frame; later ones that frame are dropped.
`[Decals] bDecals` turns decals off ([graphics options](/engine/graphics-options.md)).

## Skin decals

With `[Decals] bSkinnedDecals` on, a hit on an actor puts its decal on the actor instead of on
the ground:

- The decal rides the body bone whose origin is nearest the hit point, and faces out from
  that bone. Weapon, shield, quiver, camera, magic, arrow, and root nodes are not body bones.
  The bone moves with the animation, so a mark on a forearm follows the arm.
- An actor with no pose, or a hit with no body bone, keeps the decal in the actor's own frame
  (its feet, turned to its facing), facing out from its middle, level with the ground.
- Each frame with skin decals rebuilds the decal batches. A decal whose bone is gone, such as
  on a body part the actor no longer has, is not drawn.
- It draws as a box around the decal, not as a flat quad. Each pixel the box covers reads
  the scene depth and finds the surface point there. The texture draws where that point lies
  inside the box, so the mark wraps around an arm or a head. The box reaches as far in front
  of and behind the decal as its widest half side.
- A frame with skin decals copies the scene depth, as the water does
  ([water](/rendering/water.md)). The boxes draw right after the copy. A frame with no copy,
  such as one with a non-perspective camera, draws them as flat quads.
- The box marks only skinned meshes, as the game does. Each skinned mesh that writes depth
  sets one stencil bit (the top bit of the 8-bit stencil) where it draws, and the box draws
  only where that bit is set. The depth split keeps the stencil, so the bit is still there
  after the copy. The ground near the feet and a held weapon stay clean. The SWF clip
  counts use the 7 bits below it.
- Its width and height are at most 16 units.
- `[Display] uMaxSkinDecals` limits the live skin decals, 35 when the settings give none.
  `iMaxSkinDecalsPerFrame` limits those placed in one frame. `bDecals` off also turns them off.

## Approximations

- A skin decal marks every skinned mesh inside its box, so a second actor standing in the box
  is marked too. Picking the bone by the nearest origin, the
  box depth, the 16-unit size cap, and the default limit of 35 are OpenSky's own.
- A decal is one flat quad. It does not wrap around a corner or follow uneven ground.
- The 2 x 2 subtexture grid is a reading of the vanilla blood textures, not a confirmed rule.
- Vanilla footstep `IPCT` records have a dust model and no decal, so steps leave no marks.
