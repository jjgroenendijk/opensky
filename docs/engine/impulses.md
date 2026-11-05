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
the install does not define keeps its engine default from the UESP page
"Skyrim Mod:Mod File Format/GMST/Defaults". The CK wiki pages
`fKnockdownCurrentHealthThreshold` and `fKnockdownBaseHealthThreshold`
(<https://ck.uesp.net/wiki/FKnockdownCurrentHealthThreshold>) say what the two thresholds
mean. No source gives the formulas, so every formula below is OpenSky's reading. Issue #1689
tracks measuring them in the game.

## Hits

A melee or ranged hit that lands and does not kill knocks its target back, away from the
attacker, when its damage is at least `fKnockdownCurrentHealthThreshold` (50) percent of the
target's current health.

- The push covers `damage * fKnockbackDamageMult` (5) units, at most `fKnockbackForceMax`
  (128), in `fKnockbackTime` (0.3) seconds.
- The hit knocks down when its damage is at least `fKnockdownBaseHealthThreshold` (75)
  percent of base health, or when a roll falls below `fKnockdownChance` (0.25). A knockdown
  pushes the full `fKnockbackForceMax`.
- A ranged hit pushes `fProjectileKnockMultBiped` (0.25) times as far.

Example: a 20 point swing on an actor with 40 of 100 health pushes 100 units in 0.3 seconds.

The game ragdolls a knocked-down actor. OpenSky has no ragdoll for a living actor yet
(issue #1658), so a knockdown is a longer push on the capsule.

## Explosions

An `EXPL` force falls off linearly to zero at the radius, as its damage does.

- A loose body takes `force * fExplosionForceMultLinear * fGameplayImpulseMult<kind>` Havok
  units, measured at its nearest side, times 69.99 to reach engine units. The kind comes
  from the body's collision layer: `L_PROPS` uses `...Prop` (0.1), `L_DEBRIS_LARGE` uses
  `...DebrisLarge` (1), the trap layers use `...Trap` (0.15), and every other layer uses
  `...Clutter` (1). The layer numbers are the install's `COLL` record indices.
- The push points away from the blast, raised by `fExplosionForceClutterUpBias` (0.5).
  The same impulse at the nearest side turns the body, times `fExplosionForceMultAngular`.
- A body lighter than `fGameplayImpulseMinMass` (5 kg) changes speed as if it weighed that.
- The object the projectile struck takes `fExplosionSourceRefMult` (3) times the push.
- An actor in the radius is knocked along the ground at
  `force * fGameplayImpulseMultBiped (0.04) * 69.99` units per second, the reading the
  cloak knock in [magic archetypes](/engine/magic-archetypes.md) also uses.

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

- An actor or a loose body that goes below the surface shows `sSplashParticles` there. A key
  that first appears under water does not splash, because it may have loaded there.
- The splash sound is the `SNDR` `PHYWaterSplash`, because no setting names one. A body of
  `fSplashSoundLight` (5 kg) or more plays it; lighter bodies splash in silence. The
  `...Medium` (20) and `...Heavy` (35) tiers are kept in the readout. An actor splashes
  heavy.
- An explosion within `fExplosionSplashRadius` (250) units of the surface shows
  `sExplosionSplashParticles`. `Update.esm` sets that model to `FXEmptyObject.nif`, so
  nothing shows in the unmodded game. Under water the blast radius shrinks by
  `fExplosionWaterRadiusRatio` (0.1).
- An actor in water that flows at `fWaterKnockdownVelocity` (5) times its size factor or
  faster is knocked down along the flow, once per entry. The factor is
  `fWaterKnockdownSizeSmall` (0.6), `...Normal` (0.75), `...Large` (1.25), or
  `...VeryLarge` (1.5), by the RACE `DATA` size. The fastest vanilla water type,
  `RiverWaterFlowSE`, flows at about 2.8, so nothing in the unmodded game passes.

## Checking it in the game

`openskycli game state impulses` shows the settings in use and the newest knocks, pushes,
splashes, physics hits, and collisions (`speedLoss`, `gain`, `material`). `openskycli game debug
knock <ref> <damage>` knocks an actor back as a melee hit from the player would.
