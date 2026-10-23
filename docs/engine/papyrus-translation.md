---
type: Subsystem
title: Papyrus translation
description: How TranslateTo moves a reference over time - the speeds, the events, how the
  renderer draws the move, and where OpenSky differs from the game.
tags: [engine, papyrus, rendering]
---

# Papyrus translation

`TranslateTo` moves a reference to a position and rotation over time. Doors, platforms, and
critters use it. Sources: the Creation Kit wiki pages
[TranslateTo](https://ck.uesp.net/wiki/TranslateTo_-_ObjectReference),
[SplineTranslateTo](https://ck.uesp.net/wiki/SplineTranslateTo_-_ObjectReference),
[TranslateToRef](https://ck.uesp.net/wiki/TranslateToRef_-_ObjectReference),
[OnTranslationAlmostComplete](https://ck.uesp.net/wiki/OnTranslationAlmostComplete_-_ObjectReference),
and [OnTranslationFailed](https://ck.uesp.net/wiki/OnTranslationFailed_-_ObjectReference).

## The natives

| Native | Arguments |
| --- | --- |
| `TranslateTo` | x, y, z, angle x, y, z, speed, max rotation speed = 0 |
| `SplineTranslateTo` | x, y, z, angle x, y, z, tangent magnitude, speed, max rotation speed = 0 |
| `StopTranslation` | none |

`TranslateToRef` and `SplineTranslateToRef` are not natives. They are script functions in
`ObjectReference` that call the two natives with the target's position and angles, so they run
through the VM.

The position is in world units. The angles are in degrees. The speed is units per second, and
the rotation speed degrees per second. A rotation speed of 0 means no cap: the rotation arrives
with the position. A cap can only slow the turn, so the reference may keep turning after it
arrived. Each axis turns the short way round.

## The events

| Event | When |
| --- | --- |
| `OnTranslationAlmostComplete` | Once, on the first frame with 0.25 s or less of travel left |
| `OnTranslationComplete` | When the position and the rotation have arrived |
| `OnTranslationFailed` | When a new request replaces a move that is still running |

The wiki gives no lead time for the almost-complete event. OpenSky chose 0.25 s. A frame long
enough to finish the move sends the almost-complete event first, so a script that waits for it
always hears it.

## How the move is drawn

A transform write to the world state rebuilds the reference's cell. That is too slow for every
frame. So the script bridge keeps each running move itself and publishes the drawn poses. The
renderer turns each pose into a delta from the built placement, the same way it draws carts and
physics bodies ([dynamic body drawing](/engine/dynamic-body-drawing.md)). The world state gets
one transform write, when the move ends or stops.

While a move runs, `GetPositionX`, `GetAngleZ`, `GetDistance`, and the other script reads see the
live pose. A walking actor's position still comes from its locomotion.

## Where OpenSky differs from the game

| Behaviour | What OpenSky does | Why |
| --- | --- | --- |
| `SplineTranslateTo` | Moves in a straight line | The wiki does not define the spline from the tangent magnitude |
| `StopTranslation` | Sends no event | The failure event names a new request, and a stop is not one |
| `SetPosition`, `SetAngle`, `MoveTo` during a move | End the move, with no event | The script placed the reference on purpose, so the move must not undo it |
| A move in a save | Not saved | The save holds the last stored transform. A loaded game starts with no move |
| A reference whose cell unloads | The move ends with no event | There is nothing resident to move |
| Collision | The moving reference does not push bodies | The move is drawn, not simulated |
