---
type: Subsystem
title: Perception and detection
description: How an observer sees and hears a target - view cone, line of sight, gait noise,
  the detection value, and how it builds into unaware, suspicious, and detected - with the
  source of every constant and the inputs still missing.
tags: [engine, ai, perception, detection, stealth, sneak]
---

# Perception and detection

This page covers what one observer makes of one target: how the detection value is computed,
how it builds up into a state, and which inputs are still missing. What an alerted actor then
does is on the [combat](/engine/combat.md) page.

Sources:

- UESP, "Skyrim:Sneak", section "Remaining Undetected"
  (<https://en.uesp.net/wiki/Skyrim:Sneak>): the detection value, the attenuation, and the sound
  factor with its settings.
- UESP, "Skyrim:Skills" (<https://en.uesp.net/wiki/Skyrim:Skills>): the starting skill level.
- xEdit `Core/wbDefinitionsTES5.pas`: the condition function indices.
- Creation Kit wiki: what `GetDistance`, `GetLineOfSight`, and `GetDetected` return.

## One evaluation

Perception runs on the same 1/60 s fixed step as combat and actor values, and stops when the
world is paused. One evaluation of an observer and a target:

1. Distance, feet to feet.
2. View cone: a wedge of `viewConeHalfAngleDegrees` on each side of the observer's facing. It is
   flat in XY, because no actor tilts its head here.
3. Line of sight: one ray from the observer's eye to the target's eye, against fixed collision.
   Actors do not block it. A guard behind another guard can still see the player. Interaction
   targeting makes the same choice.
4. The detection value, from the three above plus the target's gait and crouch.
5. The pair's level goes up or down, and the level gives a state.

The ray uses the exact ray test, not the swept shape a projectile uses, because a sight line has
no thickness. A pair beyond the range of both senses is skipped before the ray, because the
attenuation would make everything zero anyway.

Observers are actors something already simulates: hostile to the player, engaged by the combat
behavior, or running a package. The only target is the player. The target list is a list so it
can grow later without changing the evaluation.

## The formula

UESP gives the whole shape, and it is used as written:

```text
Detection Value = fSneakBaseValue
    + (Sound factor + Visual factor + Noticer skill factor) * attenuation
    + (Noticer skill factor - Sneaker skill factor)

attenuation  = ((fSneakMaxDistance - distance) / fSneakMaxDistance) ^ exponent
Sound Factor = fSneakSoundsMult * (Movement + Action)
               * (1 with line of sight, fSneakSoundLosMult without)
Movement     = (equippedWeightBase + equippedWeightMult * weight)
               * gait multiplier * muffle,   0 when not moving
Action       = ActionSound * fSneakActionMult
```

The last term, `(Noticer - Sneaker)`, is left out of the code. Both skills use the same pinned
value, so it is always zero, and writing it out would suggest it is not.

Outdoors, the attenuation range is multiplied by `fSneakExteriorDistanceMult`. So the same
distance counts for less in the open than in a corridor.

UESP describes the visual factor only in words: light level drives it. Light level is not
available here, so this shape is OpenSky's own:

```text
Visual Factor = 0 without a sight line, or outside the view cone
              = visualBaseValue * lightFactor * (sneakVisualMult while crouched)
```

There is no partial seeing. A target outside the cone or behind a wall can only be heard.

### Gait multipliers

| Gait | Multiplier | Source |
| --- | --- | --- |
| Standing still | 0 | Vanilla rule |
| Sneak | `sneakMovementMult` = 0.75 | OpenSky |
| Walk, swim | 1 | Vanilla base |
| Run | `fSneakRunningMult` = 2 | `Skyrim.esm` |
| Sprint | `sprintMovementMult` = 3 | OpenSky |

Vanilla's movement term has no crouch factor. Vanilla uses the Sneak skill on the other side of
the formula instead. OpenSky has no skills yet, so sneaking has to lower the gait term. Swimming
uses the walking value instead of a new unmeasured constant.

### Noise radius

The noise radius is how far a target at one gait can be heard, in world units. It is the
distance where the sound and skill terms exactly cancel `fSneakBaseValue`. The evaluation does
not use it. The readout shows it, because a radius in world units is easy to check. Zero is a
real answer: a target too quiet to notice even up close has no radius.

Where each constant comes from, and which inputs are still fixed at a neutral value, is on the
[detection constants](/engine/detection-constants.md) page.

## Level and state

UESP describes detection as "an entire system of Stealth Points, like hit points but for
stealth". The visible behavior depends on that: the eye opens slowly, and a guard looks over and
goes back to work. A yes or no answer per frame would flicker at every doorway. So each pair has
a level from 0 to 100:

- A positive detection value adds `min(1, value / fullDetectionValue) * gainPerSecond` per
  second, and stores the target's position as the place to investigate.
- A value of zero or less removes `decayPerSecond` per second. At zero the stored position is
  forgotten, so an old position is never visited.

| Level | State |
| --- | --- |
| Below `suspiciousLevel` | Unaware |
| From `suspiciousLevel` | Suspicious |
| At `detectedLevel` | Detected |

`GetDetected` is true only in the detected state. A suspicious observer has detected nothing. It
has a place to look.

With these values, a target at full signal is detected in 1 second. A target that disappears
from a full level drops below suspicious at 3.75 seconds and is forgotten at 5 seconds.

## Limits and repeatability

Every observer against every target, with a ray per pair, grows fast with the world. Three
limits keep it bounded, and each reports what it cut:

- At most 64 pairs. The nearest pairs win, and a counter shows how many were dropped. A silent cut
  would read as "nothing else was near".
- At most 8 pairs evaluated per step, in turn, in a fixed order. A pair gets the time since its
  last evaluation. So slicing changes when a level is computed, not where it ends up.
- At most 8 steps per frame, like combat and actor values.

The list of actors is refreshed once per frame and sorted by `ReferenceKey`. Every change is a
pure function of the elapsed time. So two runs with the same inputs give the same levels.

## Condition functions

Three functions read a detection snapshot. Indices are the stored numbers from xEdit. The
Creation Kit adds 4096 to each.

| Stored | Creation Kit | Name | Parameter | Returns |
| --- | --- | --- | --- | --- |
| 1 | 4097 | `GetDistance` | a reference | World units between run-on and parameter |
| 27 | 4123 | `GetLineOfSight` | a reference | 1 if the run-on's sight line to it is clear |
| 45 | 4141 | `GetDetected` | an actor | 1 if the run-on actor has detected it |

The run-on reference asks about the parameter: `[Observer].GetDetected Target`. Detection is not
symmetric. A guard may see the player while the player does not know it is there. Asking about a
reversed pair, which is not tracked, fails as unavailable. An untracked pair is not an undetected
one. See [condition evaluation](/engine/conditions.md).

When an actor in combat loses a target that perception was tracking, it goes to the stored
position. `GetCombatState` then returns 2, "Searching". Combat music keeps playing while an actor
searches.

## Controls

- World > AI & Navigation > Overlays > Detection: draws, for each observer, a flat cone at its
  feet out to the range its senses reach. The color is grey, amber, or red for the strongest
  state. A white line points to the place it will investigate. The overlay uses depth, so a wall
  hides the cone behind it ([navigation](/engine/navigation.md)).
- World > AI & Navigation > Detection: the totals, one line per tracked pair of the selected
  actor, and every constant with its source. This section has no controls on purpose. A control
  that set a level directly would show a number the formula never made.
- `openskycli gmst detection` prints every setting with its source, and
  `openskycli gmst list --prefix <s>` prints any group of game settings ([CLI](/tools/cli.md)).
