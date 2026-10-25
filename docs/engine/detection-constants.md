---
type: Subsystem
title: Detection constants
description: Every constant in the detection formula with its source - game settings read
  from the load order, OpenSky's own values, and the inputs fixed at a neutral value.
tags: [engine, ai, perception, detection, stealth, gmst]
---

# Detection constants

The formula that uses these is on the [perception and detection](/engine/detection.md) page.

## Settings from the load order

Values from `openskycli gmst list fsneak` on the local install:

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
| `iSoundLevelSilent` | 10 | Action sound of a silent weapon or spell |
| `fSneakLightMult` | 0.33 | Scales the light term |
| `fSneakLightExteriorMult` | 0.5 | Scales the light term outdoors (OpenSky's reading) |
| `fDetectionSneakLightMod` | 15 | Added to the light level in the light term |
| `iLightLevelInteriorMod` | 25 | Added to an interior light level |
| `iLightLevelMax` | 300 | Cap on the light level |
| `fSneakLightMoveMult` | 0.01 | Visual term bonus for a moving target |
| `fSneakLightRunMult` | 0.2 | Visual term bonus for a running target |
| `fSneakStealthBoyMult` | 0 | Visual term of an invisible target |
| `fSneakAlertMod` | 0 | Noticer skill weight of a suspicious observer |
| `fSneakSleepBonus` | 0 | Noticer skill weight of a sleeping observer |
| `fSneakCombatMod` | -0.4 | Noticer skill weight of an observer fighting someone else |
| `fSneakSleepMod` | 0 | Added to a sleeping observer's value (OpenSky's reading) |
| `fPlayerDetectionSneakBase` | 10 | Base of the player's sneaker factor (OpenSky's reading) |
| `fPlayerDetectionSneakMult` | 0.4 | Skill weight of the player's sneaker factor (OpenSky's reading) |
| `fPlayerDetectActorValue` | -30 | Lowest value against the player (OpenSky's reading) |
| `fSneakFlyingDistanceMult` | 3 | Range multiplier of a flying observer |

The values are from `openskycli gmst list` on the local install. `Skyrim.esm` does not set
`fSneakLightMoveMult`, `fSneakLightRunMult`, `fSneakStealthBoyMult`, or `fSneakCombatMod`, so the
engine's own default applies. A plugin that sets one wins. "OpenSky's reading" marks a setting whose
use no source states.

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
| `sneakVisualMult` | 0.5 | Visual term while crouched; the CK wiki's visual factor has none |
| `normalActionSound` | 25 | Action sound at the normal level |
| `loudActionSound` | 50 | Action sound at the loud level |
| `veryLoudActionSound` | 100 | Action sound at the very loud level |
| `fullLightLuminance` | 1 | Light luminance that reads as light level 100 |
| `fullDetectionValue` | 25 | Value at which the level climbs at full speed |
| `gainPerSecond` | 100 | Level gained per second at full speed |
| `decayPerSecond` | 20 | Level lost per second when nothing is noticed |
| `suspiciousLevel` | 25 | Level at which the observer has a place to check |
| `detectedLevel` | 100 | Level at which the observer has the target |

UESP names three of these as game settings: `fSneakDistanceAttenuationExponent`,
`fSneakEquippedWeightBase`, and `fSneakEquippedWeightMult`. The install has no settings with
those editor IDs. When a secondary source and the shipped game disagree, the game wins, so these
stay OpenSky constants.

The install has a game setting for the silent sound level only. The other three levels have no
`iSoundLevel*` setting in `Skyrim.esm`, so their values are ours. They keep the order the record
enum implies: silent, normal, loud, very loud.

## Inputs

| Input | Source |
| --- | --- |
| Both skill levels | The `Sneak` actor value of the observer and of the target |
| Muffle | The target's `Movement Noise Mult` actor value |
| Invisibility | The target's `Invisibility` actor value, above zero |
| Blindness | The observer's `Blindness` actor value |
| Fighting another | The observer's combat target is not the judged target |
| Sleeping | The observer runs a sleep package |
| Armour weight | The sum of the `ARMO` weights the target has equipped |
| Action sound | The swing's `WEAP` `VNAM`, or the cast's first `MGEF` casting sound level |
| Light level | The scene light at the target ([light level](/engine/detection.md#light-level)) |

Only the player is a target, so only the player's inputs are sampled.
