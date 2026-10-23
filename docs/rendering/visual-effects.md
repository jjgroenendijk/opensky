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
| A script | `VisualEffect.Play` or `EffectShader.Play` on a reference | The `afTime` argument, or until `Stop` when it is negative |
| The Effects panel | Any `RFCT`, `EFSH`, `ADDN`, or `ARTO`, on the player or the nearest actor | Until cleared |

An `RFCT` is resolved to its `ARTO` model and its `EFSH` membrane. Its flag 0x02 (attach to
camera) draws the art at the camera eye instead of the target. With flag 0x04 (inherit
rotation) the art also turns with the view: its +Y points along the view and +Z up. The
opening cart ride plays two such effects through `FXCameraAttachScript`:
`FXCameraAttachBlowingFogEffect` and `FXCameraAttachUpSnowEffect`, both with flags 6. Their
models are particle systems whose box emitter sits 300 units in front of the eye. A lasting
effect that is already on the same anchor is not attached twice, so a reload does not stack
race glows.
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

## Blood

The blood game settings name textures and numbers but not the rules
(<https://ck.uesp.net/wiki/Category:Settings>), so each use is OpenSky's reading.

Screen blood: a melee or ranged hit on the player places splatters.

- Count: `fBloodSplatterCountBase` plus `fBloodSplatterCountDamageMult` per point of damage
  above `fBloodSplatterCountDamageBase`, varied by up to `fBloodSplatterCountRandomMargin`.
  `Skyrim.esm` does not set these four; OpenSky uses the wiki values 2, 0, 0.1, and 1. At most
  `iBloodSplatterMaxCount` (25) show at once.
- Size: between `fBloodSplatterMinSize` and `...MaxSize`, as a share of the screen height.
- Opacity: between `fBloodSplatterMinOpacity` and `...MaxOpacity`. With chance
  `fBloodSplatterOpacityChance`, the fainter `...Opacity2` range instead.
- Fade: full for `fBloodSplatterFadeStart` of `fBloodSplatterDuration`, then down to nothing.
- Look: `sBloodSplatterColor01OPTFilename` gives the colour, and the alpha channel of
  `sBloodSplatterAlpha01OPTFilename` the shape. Each splatter has a flare
  (`sBloodSplatterFlare01Filename`) of `fBloodSplatterFlareSize`, offset by
  `fBloodSplatterFlareOffsetScale` splatter sizes, at `fBloodSplatterFlareMult` opacity.
- The quads draw after the world and before the SWF menus and the UI.

Weapon blood: a melee hit on an actor whose race lacks the no-weapon-blood flag makes the
attacker's weapon bloody. A weapon model holds blood shapes, whose effect shader sets the
`Weapon_Blood` flag ([effect shapes](/formats/nif-materials.md#effect-shapes)). They stay
hidden on a clean weapon. On a bloody one they draw blended, with their alpha times the blood's
strength: full for `fWeaponBloodLifetime`, fading over `fWeaponBloodFadeDuration`, and gone
below `fWeaponBloodFalloffThreshold`. The first-person weapon draws its blood in the arms pass.

Default blood: a hit on an actor that its impact data shows nothing for plays
`sBloodParticleMeleeDefault` or `sBloodParticleDefault` and places the `sBloodTextureDefault`
decal on the ground. `Skyrim.esm` leaves both models empty. The decal is 24 to 48 units wide,
OpenSky's numbers.

## Approximations

- The membrane and particle textures of the `EFSH` are not sampled. The membrane is a flat
  color with a rim term.
- The fill color has three keys in the record. OpenSky uses key 1 only.
- The NIF particle systems inside an effect model run while the effect lives. When the anchor
  moves, the emitter moves with it. A world-space system (nif.xml `World Space`, the default)
  keeps its born particles where they are; a local-space one carries them along. `EFSH`
  particles are not drawn.
- Art and membranes follow the actor's feet and facing, not a named bone. The `RFCT` node
  index is not used.
- [WARNING] The `RFCT` flag 0x01 (rotate to face target) is not used, because
  `VisualEffect.Play` does not pass its facing object on yet.
- An actor's membrane covers every mesh drawn for that actor, including worn armor.

## Checking it in the app

`World > Effects > Visual Effects` holds a record picker (`VisualEffectNameControl`) with the
record's details, buttons to attach it to the player or the nearest actor, a clear button, and
the live effects (`VisualEffectStatsLabel`). `World > Effects > Impacts & Decals` turns screen
blood on and off (`ScreenBloodControl`), splashes it as if the player was hit
(`ScreenBloodSplashControl`), and lists the blood settings. The launcher's Graphics page has the
same Screen blood option.
