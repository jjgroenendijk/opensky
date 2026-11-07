---
type: Engine
title: Impulses, knockback, and splashes
description: How hits, explosions, and projectiles push actors and loose objects, how a fast
  heavy object hurts, and where things splash into water, with the game settings each rule
  reads.
tags: [engine, combat, physics, water]
---

# Impulses, knockback, and splashes

A push moves an actor along the ground on its capsule, or gives a loose object (a dynamic
body, see [dynamic bodies](/engine/dynamic-bodies.md)) an impulse. An impulse is a sudden
change of momentum, in kilogram units per second.

Sources: the setting values come from the install (`openskycli gmst list fKnock`). A setting
the install does not define keeps its engine default from the CK wiki settings list
(<https://ck.uesp.net/wiki/Category:Settings>) or the UESP page
"Skyrim Mod:Mod File Format/GMST/Defaults". The CK wiki pages
`fKnockdownCurrentHealthThreshold` and `fKnockdownBaseHealthThreshold`
(<https://ck.uesp.net/wiki/FKnockdownCurrentHealthThreshold>) say what the two thresholds
mean. The formulas come from a clean-room read of the game's behaviour. The RACE flags
"Not Pushable" (0x400) and "No Knockdowns" (0x400000) come from UESP
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RACE>).

## Hits

A melee hit that lands and does not kill knocks its target back, away from the attacker.
A blocked hit takes no push, and neither does a race with the "Not Pushable" flag.
A ranged hit pushes no actor; its knock values push loose bodies only.

- The push covers `(damage * fKnockbackDamageMult + fKnockbackDamageBase) *
  (fKnockbackAgilMult * 50 + fKnockbackAgilBase)` units, at most `fKnockbackForceMax` (128),
  in `fKnockbackTime` (0.3) seconds. The 50 is a fixed agility, because Skyrim has no
  agility attribute.
- The hit knocks down when its damage is over `fKnockdownBaseHealthThreshold` (75) percent of
  base health.
- Otherwise, when its damage is over `fKnockdownCurrentHealthThreshold` (50) percent of
  current health, it rolls a per-mille chance of `(damage * fKnockdownDamageMult (0.3) +
  fKnockdownDamageBase) / (fKnockdownAgilMult * 50 + fKnockdownAgilBase)`, at most
  `fKnockdownChance` (0.25).

Example: a 20 point swing pushes `(20 * 5 + 50) * 0.6 = 90` units in 0.3 seconds. On an actor
with 30 of 100 health it knocks down with a chance of `20 * 0.3 / 50 = 0.12`.

A knockdown ragdolls the actor ([knockdown](/engine/ragdoll.md#knockdown)). Each body gains the
slide speed over 69.99, in Havok metres a second.

## Explosions

An explosion's damage falls off as `1 - (d / R)^2` at distance `d` in radius `R`. Its push
does not fall off: every loose body in the radius takes the same push.

- The impulse is `force * fGameplayImpulseScale (150) * fGameplayImpulseMult<kind>`, in
  engine units. The kind comes from the body's collision layer: `L_PROPS` uses `...Prop`
  (0.1), `L_DEBRIS_LARGE` uses `...DebrisLarge` (1), the trap layers use `...Trap` (0.15),
  the biped layers use `...Biped` (0.04), and every other layer uses `...Clutter` (1). The
  layer numbers are the install's `COLL` record indices.
- A body lighter than `fGameplayImpulseMinMass` (5 kg) takes `mass / 5` of it. The object the
  projectile struck takes `fExplosionSourceRefMult` (3) times the force. No impulse passes
  `fExplosionMaxImpulse` (8000).
- The push points away from the blast centre, times `fExplosionForceMultLinear`. A biped body
  adds `fExplosionForceClutterUpBias` (0.5) upward. Each axis of the turn is a random part of
  the impulse, from minus to plus, times `fExplosionForceMultAngular`.
- The `EXPL` flags pick how a blast treats actors: 0x4 always knocks them down, 0x8 knocks
  them down by the hit formula above with the blast's damage, and a blast with neither does
  not knock. An actor knocks down only where the falloff is over
  `fExplosionForceKnockdownMinimum` (0.15).

Example: a force of 6 pushes a 10 kg crate with `6 * 150 = 900` kilogram units per second at
any distance in the radius.

## Projectiles

A projectile that strikes a loose body pushes it along its flight by the `PROJ` impact
force times `fProjectileKnockMultClutter` (0.15), `...Prop` (1), or `...Trap` (0.05).
`fProjectileKnockMinMass` (5 kg) works as `fGameplayImpulseMinMass` does. No large-debris
setting exists, so large debris moves as clutter.

## Physics damage

A loose body moving at `fPhysicsDamageSpeedMin` (500) units per second or faster hurts an
actor its bounding sphere touches. The damage is the heaviest `fPhysicsDamage<n>Mass` tier
the body reaches (20 kg: 1, 50 kg: 5, 100 kg: 10), times
`fPhysicsDamageSpeedBase + fPhysicsDamageSpeedMult * speed`. One contact hurts once.

## Collision sounds

A loose body that loses at least `BodyCollisionTracker.minimumSpeedLoss` (150) units per second
between two steps has hit something, and makes a sound. The body's material (`MATT` of its first
collision shape) names the impact data set in `HNAM`, through its parents if it names none
([MATT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MATT)). The surface the body
touched last picks the set's entry, as it does for a weapon blow. That surface is the `MATT` of
the static shape or the other body. A shape that names none, such as the land, takes the
material of the land texture under the contact point. The impact plays its sound and its model
at the body. A harder hit is louder: the level grows from 0.25 at the
threshold to full at a loss of 800. After a hit the body stays silent for 15 steps, so a bounce
or a slide does not rattle.

[WARNING] The threshold, the levels, and the quiet steps are OpenSky's values, in the
[unverified values](/engine/unverified-values.md).

## Water

Water comes from the resident exterior cells: the `XCLW` height and the `WATR` linear
velocity of the cell's water type.

- A loose body that crosses the surface, up or down, shows `sSplashParticles` there. A key
  that first appears under water does not splash, because it may have loaded there. A body
  that does not move up or down does not splash.
- Its splash value is its mass plus `fSplashSoundVelocityMult` (0.05) times its vertical
  speed, times `fSplashSoundOutMult` (0.5) when it leaves the water. A value over
  `fSplashSoundHeavy` (35) plays `CWaterLarge` at scale `fSplashScale1` (1), over
  `...Medium` (20) `CWaterMedium` at `fSplashScale2` (0.75), and over `...Light` (5)
  `CWaterSmall` at `fSplashScale3` (0.4). A lighter body splashes in silence.
- Two splashes anywhere keep `fSplashSoundTimer` (0.25) seconds apart.
- An actor splashes heavy when it goes in, and makes no splash when it comes out.
- An explosion splashes when the surface is higher than its centre plus
  `fExplosionWaterRadiusRatio` (0.1) of its radius. The splash shows
  `sExplosionSplashParticles` at radius over `fExplosionSplashRadius` (250) of its size.
  `Update.esm` sets that model to `FXEmptyObject.nif`, so nothing shows in the unmodded game.
- An actor in water that flows at `fWaterKnockdownVelocity` (5) times its size factor or
  faster is knocked down along the flow, once per entry. The factor is
  `fWaterKnockdownSizeSmall` (0.6), `...Normal` (0.75), `...Large` (1.25), or
  `...VeryLarge` (1.5), by the RACE `DATA` size. The fastest vanilla water type,
  `RiverWaterFlowSE`, flows at about 2.8, so nothing in the unmodded game passes.

## Checking it in the game

`openskycli game state impulses` shows the settings in use and the newest knocks, pushes,
splashes (`weight`, `sound`, `scale`), physics hits, and collisions (`speedLoss`, `gain`,
`material`). `openskycli game debug knock <ref> <damage>` knocks an actor back as a melee
hit from the player would.
