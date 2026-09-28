---
type: Subsystem
title: Detection constants
description: Every constant in the detection formula with its source - game settings read
  from the load order, OpenSky's own values, and the inputs fixed at a neutral value.
tags: [engine, ai, perception, detection, stealth, gmst]
---

# Detection constants

The formula that uses these is on the [perception and detection](/engine/detection.md) page.
Every constant keeps its source, shown by `openskycli gmst detection` and by the panel.

## Settings from the load order

Every constant keeps its source, shown by `openskycli gmst detection` and the panel. Values from
`openskycli gmst list --prefix fsneak` on the local install:

| Editor ID | Value | Meaning |
| --- | --- | --- |
| `fSneakBaseValue` | -15 | Where every detection value starts |
| `fSneakMaxDistance` | 2500 | Range over which both senses fade |
| `fSneakExteriorDistanceMult` | 2.1 | Range multiplier outdoors |
| `fSneakSoundsMult` | 1 | Scales the whole sound term |
| `fSneakSoundLosMult` | 0.3 | Scales the sound term through a wall |
| `fSneakRunningMult` | 2 | How much louder running is than walking |
| `fSneakActionMult` | 2 | Scales an action sound |
| `fSneakSkillMult` | 0.5 | Turns a skill level into a skill factor |
| `fSneakPerceptionSkillMin` | 0 | Bottom of the skill clamp |
| `fSneakPerceptionSkillMax` | 100 | Top of the skill clamp |

## OpenSky's own constants

Vanilla keeps these in AI code that no record describes. There is no game setting for a view
cone, how loud a crouching target is, how fast a guard decides, or how long it takes to forget.

| Name | Value | Meaning |
| --- | --- | --- |
| `distanceAttenuationExponent` | 2 | The attenuation exponent |
| `equippedWeightBase` | 12 | Noise with nothing equipped |
| `equippedWeightMult` | 0.5 | Noise per point of equipped weight |
| `sneakMovementMult` | 0.75 | Movement noise while crouched |
| `sprintMovementMult` | 3 | Movement noise while sprinting |
| `viewConeHalfAngleDegrees` | 90 | Half the view cone angle |
| `visualBaseValue` | 40 | Visual term for a lit, standing target in the open |
| `sneakVisualMult` | 0.5 | Visual term while crouched |
| `fullDetectionValue` | 25 | Value at which the level climbs at full speed |
| `gainPerSecond` | 100 | Level gained per second at full speed |
| `decayPerSecond` | 20 | Level lost per second when nothing is noticed |
| `suspiciousLevel` | 25 | Level at which the observer has a place to check |
| `detectedLevel` | 100 | Level at which the observer has the target |

UESP names three of these as game settings: `fSneakDistanceAttenuationExponent`,
`fSneakEquippedWeightBase`, and `fSneakEquippedWeightMult`. The install has no settings with
those editor IDs. When a secondary source and the shipped game disagree, the game wins, so these
stay OpenSky constants.

## Missing inputs

Four inputs are not available yet. Each is a named constant at a neutral value, not a guess. A
wrong number that moves is worse than a fixed one, because only the fixed one is visible.

| Input | Fixed at | What will supply it |
| --- | --- | --- |
| Light level | 1 | Scene light sampled per actor. The install has `fSneakLightMult`, `fSneakLightExteriorMult`, and `fDetectionSneakLightMod` for this term. They stay unused until there is a light level |
| Muffle | 1 | Magic effects |
| Action sounds | 0 | Attacks, casts, and shouts reported to perception |
| Both skill levels | 15 | Stored skills. 15 is the vanilla starting level of every skill before race bonuses |

Equipped weight is always 0, because nothing adds up the weight of an actor's equipped items
yet. So every target counts only `equippedWeightBase`, and is quieter than a vanilla actor in
armor.
