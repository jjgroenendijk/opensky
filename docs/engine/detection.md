---
type: Subsystem
title: Perception and detection
description: The fixed-step observer-target perception pass — view cone, line of sight,
  gait-based noise, the detection value and its accumulation into unaware, suspicious and
  detected states — with the formula's citations and its stated gaps.
tags: [engine, ai, perception, detection, stealth, sneak]
timestamp: 2026-08-09T00:00:00Z
---

# Perception and detection

Issue #202 gives resident actors senses. Before it, hostility was entered exactly two ways —
the player damaged an actor, or the panel toggle did it — and nothing in the engine saw or
heard anything. This page covers what one observer makes of one target: how the two terms of
the detection value are computed, how that value accumulates into a state, and which inputs
are still missing.

What an alerted actor *does* is not here. That is item 16.7, and it reads
`DetectionPairState.lastKnownPosition` to do it.

## Contents

* [The pass](#the-pass)
* [The formula](#the-formula)
* [Where each constant came from](#where-each-constant-came-from)
* [Stated gaps](#stated-gaps)
* [Detection level and states](#detection-level-and-states)
* [Bounds and determinism](#bounds-and-determinism)
* [Condition functions](#condition-functions)
* [Surfaces](#surfaces)
* [Tests](#tests)
* [References](#references)
* [See also](#see-also)

Engine: `PerceptionRuntime`, `PerceptionWorld`, `DetectionFormula`, `PerceptionSight`,
`DetectionPairState`, `DetectionSettings`, `PerceptionReadout`, `PerceptionOverlay` and
`DetectionResolution`, all in `opensky/Engine/Perception/`. App wiring:
`opensky/App/GameViewControllerPerception.swift`.

## The pass

`PerceptionRuntime` advances on the same 1/60 s fixed step and the same paused-aware world
delta as the combat loop and the actor-value runtime, and reaches the world only through
`PerceptionWorld`. One step evaluates a slice of observer-target pairs; each evaluation is:

1. **Distance**, feet to feet.
2. **View cone**, a yaw wedge of `viewConeHalfAngleDegrees` about the observer's facing.
   Flattened into the XY plane, because nothing in this engine pitches an actor's head.
3. **Line of sight**, one exact ray from the observer's eye to the target's eye against
   static collision. Actors do not block it — a guard standing behind a guard can still see
   you — which is the same choice [interaction targeting](/engine/interaction.md) makes.
4. **The detection value**, from those three plus the target's gait and crouch.
5. **Accumulation or decay** of the pair's level, and the state that level reads as.

The ray is `InteractionRaycaster.nearestHit` over the streamer's
`staticCollisionCandidates(overlapping:)` broadphase — the exact caster rather than the
`ShapeSweeper` a projectile uses, because a sight line has no thickness and there is no
`collisionRadius` to put in a sweep. A pair already past the range where either sense could
reach is skipped before the ray is cast, since the attenuation would multiply everything by
zero anyway.

**Who observes.** The session's filter, not the runtime's: an actor is an observer when it
is hostile to the player, when it is the dev target, or when the package runtime has
selected a package for it. Those are exactly the actors something in this engine is already
simulating. **Who is observed** is the player and nobody else — NPC-versus-NPC perception is
out of 16.6's scope beyond what 16.7's combat needs, and the target seam is a list precisely
so 16.7 can widen it without touching the pass.

## The formula

UESP "Skyrim:Sneak" states the whole shape, and it is implemented as written:

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

The trailing `(Noticer - Sneaker)` term is omitted from the code rather than added as a
literal zero: both skills are pinned to one constant, so it is exactly zero by construction
and writing it out would suggest otherwise.

Outdoors the attenuation range is multiplied by `fSneakExteriorDistanceMult`, so the same
distance attenuates less in the open than in a corridor.

The **visual factor** is the one term UESP describes only qualitatively — it names light
level as the driver, and light level is a gap here — so its shape is OpenSky's:

```text
Visual Factor = 0 without a sight line, or outside the view cone
              = visualBaseValue * lightFactor * (sneakVisualMult while crouched)
```

There is no partial seeing: a target outside the cone or behind a wall contributes nothing
visually and can only be heard.

### Gait multipliers

| gait | multiplier | source |
| --- | --- | --- |
| standing still | 0 | vanilla's own rule, no constant attached |
| sneak | `sneakMovementMult` = 0.75 | OpenSky |
| walk, swim | 1 | vanilla's implicit base |
| run | `fSneakRunningMult` = 2 | `Skyrim.esm` |
| sprint | `sprintMovementMult` = 3 | OpenSky |

Vanilla's movement term has no crouch factor at all — it spends the Sneak skill on the
*observer's* side of the formula instead — and OpenSky has no skills to spend, so the gait
is where sneaking has to pay. Swimming is deliberately given walking's multiplier rather
than a fourth constant nothing measured.

### The noise radius

`DetectionFormula.noiseRadius(gait:settings:isExterior:hasLineOfSight:)` inverts the
attenuation to report how far a target moving at one gait can be heard, in world units — the
distance at which the sound and skill terms alone exactly cancel `fSneakBaseValue`. Nothing
in the pass consumes it; the attenuated sound term already produces the behaviour. It exists
because "a gait-based noise radius" is what the milestone asks for in world units, and this
is that number. Zero is a real answer: a target too quiet to notice even while touching the
observer has no radius.

## Where each constant came from

Two kinds of number, kept apart on purpose, and every one of them carries its own source
string into `openskycli gmst detection` and the panel readout.

**Read from the load order.** Ten settings the shipped game carries. Values below are what
`openskycli gmst list --prefix fsneak` reported on the local install on 2026-08-09.

| editor ID | value | what it does |
| --- | --- | --- |
| `fSneakBaseValue` | -15 | the constant every detection value starts from |
| `fSneakMaxDistance` | 2500 | the range both senses attenuate over |
| `fSneakExteriorDistanceMult` | 2.1 | what that range is multiplied by outdoors |
| `fSneakSoundsMult` | 1 | scales the whole sound term |
| `fSneakSoundLosMult` | 0.3 | scales the sound term through a wall |
| `fSneakRunningMult` | 2 | how much louder running is than walking |
| `fSneakActionMult` | 2 | scales an action sound |
| `fSneakSkillMult` | 0.5 | turns a skill level into a skill factor |
| `fSneakPerceptionSkillMin` | 0 | bottom of the skill clamp |
| `fSneakPerceptionSkillMax` | 100 | top of the skill clamp |

**OpenSky's own.** Numbers vanilla keeps in AI internals that no record documents. There is
no GMST for a view cone, for how loud a crouching target is, for how fast an alerted guard
makes up its mind, or for how long it takes to forget.

| name | value | what it does |
| --- | --- | --- |
| `distanceAttenuationExponent` | 2 | the attenuation exponent |
| `equippedWeightBase` | 12 | noise before anything is equipped |
| `equippedWeightMult` | 0.5 | noise per point of equipped weight |
| `sneakMovementMult` | 0.75 | movement noise while crouched |
| `sprintMovementMult` | 3 | movement noise while sprinting |
| `viewConeHalfAngleDegrees` | 90 | half-angle of the view cone |
| `visualBaseValue` | 40 | the visual term for a lit, upright target in the open |
| `sneakVisualMult` | 0.5 | the visual term while crouched |
| `fullDetectionValue` | 25 | detection value at which the level climbs at full rate |
| `gainPerSecond` | 100 | level gained per second at a full-rate signal |
| `decayPerSecond` | 20 | level lost per second while nothing is perceived |
| `suspiciousLevel` | 25 | level at which an observer has somewhere to investigate |
| `detectedLevel` | 100 | level at which an observer has the target |

Three of these are named by UESP as settings and are still ours, because the install carries
no GMST by those editor IDs: `fSneakDistanceAttenuationExponent`,
`fSneakEquippedWeightBase` and `fSneakEquippedWeightMult`. That is a real disagreement
between a secondary source and the shipped game, and the shipped game wins — the same rule
[melee combat](/engine/melee-combat.md) applies to the block factors.

## Stated gaps

Four inputs the engine cannot supply yet. Each is a named constant on `DetectionFormula`
pinned at a documented neutral value, never approximated with a plausible-looking
substitute: a wrong number that moves is worse than a stated constant that does not, because
only one of the two is visible.

| input | pinned at | what fills it |
| --- | --- | --- |
| light level | `pinnedLightFactor` = 1 | per-actor scene light sampling. The install carries `fSneakLightMult`, `fSneakLightExteriorMult` and `fDetectionSneakLightMod` for exactly this term, and they are deliberately left unresolved until there is a light level to multiply |
| muffle | `pinnedMuffle` = 1 | magic effects |
| action sounds | `pinnedActionSound` = 0 | attacks, casts and shouts reporting to perception |
| both skill levels | `pinnedSkillLevel` = 15 | stored skills. `ActorValueIdentity` names Sneak as vanilla actor value 15, and [actor values](/engine/actor-values.md) stores three of the 164 — health, magicka and stamina — so neither the sneaker's Sneak nor the noticer's perception is readable through `ActorValueRuntime` today. 15 is the vanilla starting level for every skill before racial bonuses |

Equipped weight is wired through the seam but the app supplies zero, because nothing sums
the weight of what an actor has equipped yet; a target therefore counts as
`equippedWeightBase` alone and is quieter than a vanilla armoured one.

Pinning both skills at the same number is what makes the formula's trailing
`(Noticer - Sneaker)` term exactly zero, so the one place a skill still shows up is the
attenuated noticer term.

## Detection level and states

Detection in vanilla is described as "an entire system of Stealth Points, like hit points
but for stealth", and every visible behaviour depends on that continuity: the eye opening
gradually, a guard glancing over and going back to work. A boolean recomputed per frame
gives none of that and flickers on every doorway a sight line clips. So each pair carries a
level from 0 to 100:

* a positive detection value gains `min(1, value / fullDetectionValue) * gainPerSecond` per
  second and records the target's position as the **investigate position**;
* a zero or negative value loses `decayPerSecond` per second, and dropping to zero forgets
  the investigate position, so a stale position can never be walked to.

The level reads as three states: **unaware** below `suspiciousLevel`, **suspicious** at or
above it, and **detected** at `detectedLevel` — the top of the scale, so "detected" and
"certain" are the same state. `GetDetected` is the detected state alone; a suspicious
observer has not detected anything, it has somewhere to go and look.

At the shipped rates a full-signal target is detected in one second, and a target that
vanishes from a full level crosses back under suspicion at 3.75 s and is forgotten at 5 s.

## Bounds and determinism

Perception is the first subsystem in this engine whose cost is quadratic in the world rather
than linear: every observer against every target, with a raycast per pair. Three named
bounds, all reported rather than silent:

* `maximumPairs` (64) caps how many pairs exist. Past it the nearest pairs win and
  `droppedPairCount` says how many were refused — a silent truncation would read as "nothing
  else was nearby".
* `pairsPerStep` (8) caps how many are re-evaluated per fixed step, round-robin over a
  stable order. A pair evaluated every eighth step is advanced by the elapsed time since it
  was last looked at, so slicing changes *when* a level is recomputed and not what it
  converges to.
* `maximumStepsPerAdvance` (8) caps how much simulated time one frame may spend, exactly as
  the combat loop and the actor-value runtime cap theirs.

The roster is refreshed once per frame rather than once per step, sorted by `ReferenceKey`
before it is paired, and every accumulation is a pure function of the elapsed seconds. Two
runs over the same recorded inputs produce the same levels.

## Condition functions

Three functions register additively into `ConditionFunctionRegistry`, reading a
`DetectionResolution` snapshot on `ConditionContext` and nothing else. Indices are the raw
on-disk numbers from xEdit's condition table; the Creation Kit spells each 4096 higher.

| stored | Creation Kit | name | parameters | returns |
| --- | --- | --- | --- | --- |
| 1 | 4097 | `GetDistance` | #1 reference | world units between the run-on and the parameter |
| 27 | 4123 | `GetLineOfSight` | #1 reference | 1 when the run-on's sight line to the parameter is clear |
| 45 | 4141 | `GetDetected` | #1 actor | 1 when the run-on actor has detected the parameter actor |

All three are asked of the run-on reference *about* the parameter reference —
`[Observer].GetDetected Target`. That direction matters, because detection is not symmetric:
a guard may have you while you have no idea it is there. Asking the reversed pair, which the
pass does not track, is `ConditionFailure.unavailableDetection` rather than a "not
detected" — an untracked pair is not an undetected one, and only one of those is a real
answer. The failure has its own `ConditionTally` bucket. See
[conditions](/formats/conditions.md).

`GetCombatState`'s third return, 2 "Searching", still is not produced: the state exists here
as `DetectionState.suspicious`, and wiring it into combat state is 16.7's, together with the
music runtime's matching seam.

## Surfaces

* **World overlay.** `PerceptionOverlay` contributes to the
  [world debug overlay](/engine/navigation.md#world-debug-overlays) registry under the
  `detection` identifier, behind `Renderer.detectionOverlayEnabled`. Per observer it draws a
  flat cone fan at the feet — the full view angle, out to the range that observer's senses
  actually reach, coloured grey, amber or red by the strongest state it holds — and a white
  line to its investigate position, so "it heard something over there" is visible as a thing
  pointing somewhere rather than as a state name. The pass is depth-tested, so a cone
  disappears behind the wall that blocks it.
* **Panel seam.** `PerceptionControlProviding` supplies the readout and the settings with
  their provenance; the controls that show them arrive with the M16 gate panel (issue #203)
  under the accessibility identifier `DetectionStatsLabel`.
  `DetectionPairReadout.summaryLine` *is* that line, so the panel prints one string rather
  than re-deriving a format the tests would then have to know twice.
* **CLI.** `openskycli gmst detection` prints every resolved setting with its source, and
  `openskycli gmst list --prefix <s>` prints any GMST family — the probe the tables above
  were read with. See [the CLI reference](/tools/cli.md).

## Tests

* `DetectionFormulaTests` — the attenuation including its exterior multiplier and its
  non-finite input, each of the three terms, the gait table, the pinned constants, sneaking
  against standing at the same pose, a blocked sight line at two gaits, and the ordering of
  the four noise radii.
* `PerceptionRuntimeTests` — a target behind a wall, a target outside the cone that is still
  heard, the cone as a yaw wedge, sneaking versus standing accumulation rates, the decay
  schedule, the investigate position surviving the target moving on, repeatability over the
  same inputs, the pair cap and its dropped count, the ray cost of slicing, a pair past
  every range costing no ray, the paused frame, the readout line, the condition seam and the
  overlay.
* `ConditionDetectionFunctionTests` — the three functions at their xEdit indices, both
  directions of a pair, an empty seam, a parameter naming no reference, and an unplaced
  reference.
* `PerceptionRealDataTests` (env-gated) — every load-order setting resolving from
  `Skyrim.esm` rather than from a fallback, and a real `GuardWhiterun*` ACHR moving through
  unaware, suspicious and detected as the player walks 2800 units toward it across the real
  Whiterun collision geometry.

Every synthetic fixture is built in code (`PerceptionFixture`, `FakePerceptionWorld`); no
game bytes are committed.

## References

* UESP, "Skyrim:Sneak", section "Remaining Undetected" —
  <https://en.uesp.net/wiki/Skyrim:Sneak>. The detection-value shape, the attenuation, and
  the sound factor with its named settings.
* UESP, "Skyrim:Skills" — <https://en.uesp.net/wiki/Skyrim:Skills>. The vanilla starting
  skill level the pinned skill constant uses.
* xEdit dev-4.1.6, `Core/wbDefinitionsTES5.pas` —
  <https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas>. The
  condition-function index table.
* Creation Kit wiki, `GetDistance`, `GetLineOfSight` and `GetDetected` return semantics.

## See also

* [Conditions](/formats/conditions.md) — the CTDA payload, the registry and the tally.
* [Actor package schedules](/engine/package-schedules.md) — what makes an actor an observer.
* [Combat loop](/engine/combat.md) — where hostility lives, and what 16.7 will drive.
* [Runtime navigation](/engine/navigation.md) — the world overlay registry this draws into.
* [Actor values](/engine/actor-values.md) — why no skill is readable yet.
