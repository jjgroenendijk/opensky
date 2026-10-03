---
type: Subsystem
title: Kill cam, cinematic camera, and camera shake
description: When a kill cam plays, how a chosen camera shot moves the eye and slows the
  world, and how script camera shakes work.
tags: [engine, camera, combat]
---

# Kill cam, cinematic camera, and camera shake

A kill cam is a short scripted camera sequence after a killing blow. The game picks it from
the `CPTH` camera path tree and plays the `CAMS` shots of the chosen path. The records and the
walk that picks the shots are on the [camera records](/formats/camera-records.md#shot-selection)
page.

## When it plays

A kill cam plays when all of these are true:

- Kill cams are on (`World > Kill Cam > Kill cams`).
- The player made the kill. OpenSky learns of a death in the ragdoll death sweep, which
  does not record the killer, so it treats the player as the attacker of every hostile death.
- The dead actor was hostile to the player.
- No other hostile actor in combat is left. Vanilla shows kill cams only on the last enemy.
- A roll against `fKillCamBaseOdds` passes. The install sets it to 1, so every eligible kill
  plays.

The sidebar can force a kill cam on the nearest actor. That skips the odds and the
last-enemy rule.

Differences from the game:

- The game also knows the weapon and plays bow, spell, and melee paths. OpenSky has no
  projectile anchor yet, so a shot placed on the projectile uses the target instead.
- The game starts a bow kill cam before the arrow lands. OpenSky starts every kill cam after
  the death.
- Paired kill-move animations are not played, so a melee kill finds no kill-cam path and
  ends on an `Exit` path: no kill cam plays.

## Playing a shot

A shot plays in stages, one per `CAMS` action group (shoot, fly, hit, zoom).

- The eye follows the `NiCamera` in the shot's mesh. The mesh is authored around the
  anchor actor (`CAMS` location) in the actor's own frame, so OpenSky turns the track by the
  actor's heading and adds the actor's position. The track layout is on the
  [NIF](/formats/nif.md#camera-animation) page.
- With `CAMS` flag 0x02, or with no track, the camera looks at the chest of the shot's target
  actor. Otherwise it looks down the track's own +X axis, the Gamebryo camera forward axis.
- A stage lasts as long as its track: stop time minus start time. `CAMS` max time caps it,
  and min time is a floor. A shot with no track and no max time lasts 1.5 seconds. A shot whose
  min and max times are both 0 has no length: `ExitPlaybackCamHolder`, the only shot of every
  `Exit` path, is such a shot, so a walk that ends on an `Exit` path plays no kill cam.
- The camera runs at real time while the world runs slower. The world scale is the global
  time multiplier times the slower of the player and target multipliers, clamped to
  0.01...1. OpenSky has one world clock, so it cannot slow the player and the target by
  different amounts.
- A shot that names an `IMAD` starts it when its stage starts.
- The eye goes through the dialogue camera's collision probe, so it does not end inside a
  wall.

The cinematic pose writes on top of the active camera mode, like the
[dialogue camera](/engine/dialogue-camera.md). When it ends, the player's own view comes back.
A cinematic pose outranks a dialogue pose.

## Camera shake

`Game.ShakeCamera(source, strength, duration)` adds a wobble to the eye: three sine waves that
fade to zero over the duration. Full strength moves the eye by up to 6 units. A source actor
farther away shakes less, falling linearly to zero at 2,048 units. The masters set no
`fCameraShakeTime`, so a duration of zero or less uses 1 second. These numbers are OpenSky's
choice; no source gives the game's.

The shake adds to whatever pose is active: the player camera, the dialogue camera, or a
kill cam. `Game.ForceFirstPerson` and `Game.ForceThirdPerson` set the camera mode directly.
