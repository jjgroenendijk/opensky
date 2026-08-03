---
type: Subsystem
title: Behavior graph runtime
description: Evaluating a decoded Havok Behavior graph headlessly - the instance model,
  the fixed update order, generator and modifier semantics, the pose and root-motion
  output contract, and the honest-coverage tally of everything still owed.
tags: [engine, animation, havok, hkx, behavior, locomotion, milestone-14]
timestamp: 2026-08-03T00:00:00Z
---

# Behavior graph runtime

Milestone 14 item 14.3 turns the decoded behavior graph of
[HKX behavior graph objects](/formats/hkx-behavior.md) and
[HKX behavior nodes](/formats/hkx-behavior-nodes.md) into something that runs: variables,
events, bindings, generator lifecycle, clip sampling, and blends, stepped headlessly and
deterministically. Nothing here is wired to the renderer or to input. Item 14.5 supplies
engine state, item 14.6 replaces the hardcoded idle path of
[Actor idle animation](/engine/actor-animation.md), and item 14.4 adds the state machine.

The code lives under `opensky/Behavior/`, deliberately apart from the format parsers in
`opensky/Formats/HKX/`: decoding a packfile and running a graph are different jobs with
different failure modes.

## Contents

* [Instance model](#instance-model)
* [Update order](#update-order)
* [Variables](#variables)
* [Events](#events)
* [Bindings](#bindings)
* [Generators](#generators)
* [Clips](#clips)
* [Blending and pose math](#blending-and-pose-math)
* [Modifiers](#modifiers)
* [Output contract](#output-contract)
* [The tally](#the-tally)
* [Flagged assumptions](#flagged-assumptions)
* [Verification](#verification)

## Instance model

`BehaviorGraphInstance` is one running graph. It is built over a root generator, a
`hkbBehaviorGraphData`, a `BehaviorObjectSource` that answers "what is the decoded object
at this pointer target?", a `BehaviorSkeleton`, and a `BehaviorClipSource`.

Nothing about it is a singleton. Two instances over the same decoded file share the
immutable decode and nothing else — no variables, no events, no node state — which is what
item 14.7 needs when it puts a first-person graph beside the third-person one, and what
makes the determinism test meaningful.

Two sources exist. `HKXBehaviorObjectSource` decodes on demand through
`HKBClassRegistry`, which is the engine path. A test supplies a dictionary of decoded
structs it built in code, which is why the evaluator's unit tests need no packfile bytes
at all: the byte layouts are already covered by the decode tests, and repeating them in an
evaluation test would be testing the fixture.

Per-node runtime state (`BehaviorNodeState`: clip local time, cycle count, timer elapsed,
event-driven running flag) is keyed by `HKXPointerTarget`, not by path through the tree. A
behavior graph is a DAG — a bone weight array or a transition effect is shared by many
parents — and Havok keys node state the same way.

## Update order

`update(deltaTime:)` is fixed and total:

1. Everything raised since the last update becomes the active event set. Nothing raised
   *during* this update is visible to it.
2. The generator tree is walked depth first from the root, children in the order the class
   declares them. A node's bindings are applied immediately before it is evaluated, so
   every node sees the same variable values.
3. Nodes reached last update but not this one are deactivated, in packfile order (section,
   then offset).
4. The active event set closes and is returned.

Step 1 is the decision that makes the whole thing deterministic, and it is a choice rather
than an observation: an event raised by a clip trigger halfway down the tree cannot reach
a modifier that ran earlier in the same update, so the result does not depend on traversal
order. Step 3 is deterministic for the same reason — a set iterated in hash order would
fire deactivation events in a different order on every run.

Activation is implicit. A node is activated the first update it is reached and deactivated
the first update it stops being reached; `BehaviorGraphInstance.deactivate()` deactivates
everything. `BehaviorGraphInstance.maximumDepth` (64) stops a cyclic or pathological graph
and tallies `depthCapReached` rather than recursing without end.

## Variables

`BehaviorVariableStore` seeds from `hkbBehaviorGraphData`: type per index from
`m_variableInfos`, name per index from `m_stringData.m_variableNames`, initial value from
`m_variableInitialValues` — the word list for bool, int, and real (a real is its float bit
pattern stored in an i32), the quad list for vector and quaternion.

Word storage keeps the raw i32, so a round trip is byte-exact and an unrecognised declared
type still reads and writes without loss. Reads and writes coerce to the declared type
rather than failing, because a binding names a member whose Swift type is fixed while the
authored variable type is whatever the graph author chose. External callers address
variables by name; `hkbVariableBindingSet` addresses them by index, and both work.

## Events

`BehaviorEventQueue` mirrors the variable store: index, name, flags, all positional.
`raise` queues for the next update; `beginUpdate` promotes the queue into the active set;
`endUpdate` closes it and returns what the update saw. The pending queue is capped at 256
and drops oldest-first, so a modifier that raises an event every update with nothing
consuming it cannot grow it without bound.

## Bindings

A `hkbVariableBindingSet` maps a member path on the owning object to a variable index, so
writing a graph variable rewrites a node field. The evaluator resolves a node's bindings
immediately before evaluating it, never caches them across a node, and applies the
`m_indexOfBindingToEnable` binding as a node enable flag.

**Member paths in the vanilla files carry no `m_` prefix.** The probe over the install
reports `blendParameter`, `startStateId`, `selectedGeneratorIndex`, `isActive`, `weight`,
`fBlendParameter`, `currentStateId`, `fOffsetVariable` — while the decoders name their
fields after the Havok members, which do carry it.
`BehaviorGraphInstance.normalizedMemberPath` strips a leading `m_` from both sides so a
lookup written either way resolves. This was found by measurement, not assumed: the first
version of the evaluator resolved every binding correctly and then looked all of them up
under the wrong key.

A binding that cannot be applied — a character property, an out-of-range variable index, a
bit index past 32, an empty path binding the object wholesale — is recorded in the tally
rather than guessed at.

## Generators

| Class | What it does here |
| --- | --- |
| `hkbClipGenerator` | Full: see [Clips](#clips) |
| `hkbBlenderGenerator` | Weighted blend of every child; see [Blending](#blending-and-pose-math) |
| `hkbManualSelectorGenerator` | Runs the child at `selectedGeneratorIndex`; out of range is the reference pose |
| `hkbModifierGenerator` | Runs its child, then its modifier over the result |
| `hkbPoseMatchingGenerator` | Runs as its blender base; tallies `poseMatchingAsBlender` |
| `hkbStateMachine` | Start state only; tallies `stateMachineStartStateOnly` |
| `BSiStateTaggingGenerator` | Runs its default generator |
| `BSBoneSwitchGenerator` | Default generator only, per-bone children ignored; tallied partial |
| `BSCyclicBlendTransitionGenerator` | Wrapped blender only; tallied partial |
| `BSOffsetAnimationGenerator` | Default generator only, offset clip ignored; tallied partial |
| `BSSynchronizedClipGenerator` | Wrapped clip only, marker sync ignored; tallied partial |
| `hkbBehaviorReferenceGenerator` | Reference pose; tallies `unresolvedBehaviorReference` |
| anything else | Reference pose; named in `unevaluatedGenerators` |

The state machine is deliberately shallow. Transitions, wildcard transitions, transition
effects, and event-driven state changes are item 14.4's. What this item does is find the
state whose `m_stateId` matches `m_startStateId` — honouring a binding on `startStateId`,
which the vanilla data uses heavily, and `m_startStateMode` 1's read from
`m_syncVariableIndex` — and run its generator, so the tree below a state machine is
exercised at all. Mode 2 re-enters whatever was current at deactivation, which needs
transition history this item does not keep, so it falls back to `m_startStateId`.

## Clips

The clip *window* is the part of the animation a generator plays:
`m_cropStartAmountLocalTime` off the front, `m_cropEndAmountLocalTime` off the back. Every
time below is measured inside that window.

* Local time advances by `deltaTime * m_playbackSpeed`, times `window / m_enforcedDuration`
  when `m_enforcedDuration` is positive.
* `m_startTime` places a freshly activated clip.
* `m_mode` 0 clamps at the window end. Mode 1 wraps. Mode 2 reads
  `m_userControlledTimeFraction`. Mode 3, ping pong, runs as a loop and is tallied.
* Sampling goes through `HKASplineCompressedAnimation.boneLocalTransforms(at:binding:)`,
  the seam that already existed, reached through the `BehaviorClip` protocol so the
  evaluator does not care who loads the bytes.

Triggers are how a clip tells the rest of the graph where it is. Havok's annotation tracks
are baked into `hkbClipTriggerArray` at export with `m_isAnnotation` set, so decoding
`hkaAnnotationTrack` separately is not needed for the vanilla player graph: an annotation
and an authored trigger arrive through the same array and fire through the same code. A
trigger fires when the update steps over it, on the half-open interval
`(previous, current]`; `m_relativeToEndOfClip` measures back from the window end, and
`m_acyclic` fires on the first cycle only. Clip-done events are these, not a separate
mechanism.

## Blending and pose math

A pose is dense: one `HKABonePose` per skeleton bone, seeded from the reference pose,
rather than the sparse sample list a clip produces. Dense is what blending needs — two
children animating different bone subsets must still mix bone by bone, and a bone neither
animates must come out as the reference pose rather than as a hole.
`SkeletonPoseMath.worldMatrices(skeleton:samples:)` composes the same way, so the two
layers agree on what an unanimated bone is.

`BehaviorPoseMath.blend(children:fallback:)` folds left to right: after children of total
weight W, the next child of weight w enters at `w / (W + w)`. For two children of weights
a and b that is exactly `blend(first, second, weight: b / (a + b))`, and for translation
and scale the fold is exactly the weighted average — which is what the unit tests
hand-compute against. Translation and scale interpolate linearly; rotation slerps along
the shortest arc, so a turn from -10 to +10 degrees blends through 0 rather than through
180. A degenerate quaternion normalizes to the identity: malformed input must not produce
a NaN pose.

Children of non-positive weight, and children under `m_referencePoseWeightThreshold`, are
dropped rather than normalized to zero, so a blender whose weights all fall away produces
the reference pose instead of a divide by zero.

The pose blend uses `m_weight`; the root travel uses `m_worldFromModelWeight`, which is
the member whose whole purpose is to let a child drive motion without driving the pose.

## Modifiers

Implemented: `hkbModifierList` (children in order), `hkbEventDrivenModifier`
(`m_activateEventId`/`m_deactivateEventId`/`m_activeByDefault` gate the wrapped modifier),
`hkbTimerModifier` (raises `m_alarmEvent` once past `m_alarmTimeSeconds`),
`BSEventOnDeactivateModifier` (raises on deactivation), `BSEventEveryNEventsModifier`
(counts `m_eventToCheckFor`, raises `m_eventToSend` every N).

Every other modifier passes its input through unmodified and is named in
`passthroughModifiers`. That is not a silent approximation: a missing foot-IK correction
reads as a foot that does not plant, which is visibly wrong in the right way, rather than
as a foot in a plausible but invented position.

## Output contract

`BehaviorUpdateResult` is what items 14.4 through 14.6 consume:

* `bones` — local TRS per skeleton bone. The root bone is left at its reference pose.
* `rootMotion` — the root bone's travel this update, translation and rotation, **never
  applied to `bones`**. A Skyrim walk clip bakes world travel into the root, so composing
  the root like any other bone walks the whole skeleton off the origin. Item 14.5 hands
  this to the character controller and the controller decides where the character ends up.
  A clip that wraps mid-update reports the run to the window end concatenated with the run
  from the window start, not the negative jump a naive sample difference would give.
* `firedEvents` — every event the update saw, in raise order.
* `time` — seconds of graph time this instance has run.

## The tally

`BehaviorTally` is the same ranked honest-coverage ledger as `ConditionTally` and
`AS2Tally`: per-class and per-feature counters, capped name tables with uncapped totals,
and never a crash on the unimplemented. It is a first-class result, not a debug aid — it
is the answer to "which Havok Behavior classes does OpenSky still owe Skyrim?", it is what
the real-data probe ranks, and it is what the milestone gate (#191) reports.

Buckets: `unevaluatedGenerators`, `partialGenerators`, `passthroughModifiers`,
`unresolvedClips`, `unappliedBindings`, `undecodableObjects`, `featureGaps`, plus the
positive half `boundMemberPaths` (which member paths the authored data actually drives)
and the volume counters `generatorsEvaluated`, `modifiersEvaluated`, `updatesRun`.

## Flagged assumptions

These are guesses marked as guesses, in the sense AGENTS.md "How agents work here" means:

* **Blender flags are not acted on.** `HKBBlenderFields.flags` is decoded, and the local
  decode notes read bit 0 as cycle sync and bit 2 as parametric blend, but that bit map is
  not confirmed against an independent source. `blendParameter` is the most-bound member
  in the vanilla player graph (4,260 applications across 35 graphs in a 60-update probe),
  so a parametric blend is the largest single piece of locomotion still owed — and writing
  it against an unverified flag map would be exactly the invented-internals mistake the
  project forbids. Until the bit meanings are confirmed, the authored `m_weight` values
  are used as weights directly and every such blender costs one
  `blenderParametricAsWeights` entry.
* **Root motion is measured in the root bone's own local frame**, as the difference of two
  samples of that bone. Whether Skyrim's root travel needs an additional
  world-from-model term is an item 14.5 question, once a character controller exists to
  disagree with.
* **The root bone is bone 0.** True of every vanilla Skyrim rig (`NPC Root [Root]`), and
  `BehaviorSkeleton.rootBoneIndex` is configurable rather than hardcoded, but nothing
  reads the index out of the character file yet.
* **`BSEventEveryNEventsModifier.m_randomizeNumberOfEvents` is honoured as its non-random
  maximum**, because an engine that decides animation timing from an unseeded random
  source cannot be stepped deterministically. The choice is tallied.
* **Update order is a decision, not an observation.** Havok's own visibility rules for an
  event raised mid-update are not documented in any source consulted here; deferring to
  the next update is the choice that makes traversal order irrelevant to the result.

## Verification

Unit tests, all synthetic and all in code: `BehaviorPoseMathTests` (blends against
hand-computed values, shortest-arc rotation, degenerate quaternions, root-motion
concatenation), `BehaviorEvaluatorTests` (variable seeding and coercion, instance
independence, binding application, the enable binding, event ordering and one-update
visibility), `BehaviorClipTests` (time advance, playback speed, looping, single play,
start time, triggers including relative-to-end and acyclic, root motion across a loop
seam), `BehaviorGeneratorTests` (two-child blend arithmetic, threshold dropping, bound
weights, selector switching, state-machine start state, tally entries), and
`BehaviorLifecycleTests` (deactivation events, instance deactivation, and two instances
stepped identically producing identical poses and event logs).

The clip tests run over a real decoded `hkaSplineCompressedAnimation` built from the
shared synthetic packfile fixture `HKASplineFixture.swift`, so time advance is asserted
through the same sampling seam the engine uses.

The env-gated probe is
`make realtest T='BehaviorEvaluatorRealDataTests/stepsEveryPlayerBehaviorGraph()'`. It
builds one instance over each of the 35 vanilla player behavior files, third-person and
`_1stperson`, resolves their clips out of the install, and steps each 60 times at 1/30 s
with no input. It asserts zero undecodable objects, that every graph reaches a generator
and produces bones, and that every graph reaches a state machine. The report goes to
gitignored `logs/behavior-evaluator-probe.log` — counts, class names, and archive paths
only, never sample data.

Run on 2026-08-03 against the local install: 35 graphs, 37,620 generator evaluations,
5,880 modifier evaluations, 2,602 events fired, 82 clips loaded, zero clip lookups missed,
zero undecodable objects, zero unevaluated generator classes. The ranked gaps were
`stateMachineStartStateOnly` 8,880, `blenderParametricAsWeights` 4,560,
`blenderBoneWeights` 1,200, `BSEventOnFalseToTrueModifier` 960,
`hkbEvaluateExpressionModifier` 840, `BSIsActiveModifier` 720. That list is the worklist
for items 14.4 through 14.6.
