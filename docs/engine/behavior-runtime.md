---
type: Subsystem
title: Behavior graph runtime
description: Evaluating a decoded Havok Behavior graph headlessly - the instance model,
  the fixed update order, generator and modifier semantics, state machines with
  event-driven transitions and crossfades, clip synchronization, the pose and root-motion
  output contract, and the honest-coverage tally of everything still owed.
tags: [engine, animation, havok, hkx, behavior, locomotion, milestone-14]
timestamp: 2026-08-03T00:00:00Z
---

# Behavior graph runtime

Milestone 14 items 14.3 and 14.4 turn the decoded behavior graph of
[HKX behavior graph objects](/formats/hkx-behavior.md) and
[HKX behavior nodes](/formats/hkx-behavior-nodes.md) into something that runs: variables,
events, bindings, generator lifecycle, clip sampling, blends, and the state machines that
move a character between locomotion states, stepped headlessly and deterministically.
Nothing here is wired to the renderer or to input. Item 14.5 supplies engine state and
item 14.6 replaces the hardcoded idle path of
[Actor idle animation](/engine/actor-animation.md).

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
* [State machines](#state-machines)
* [Transitions](#transitions)
* [Transition conditions](#transition-conditions)
* [Crossfades](#crossfades)
* [Clip synchronization](#clip-synchronization)
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
| `hkbStateMachine` | Full: see [State machines](#state-machines) |
| `BSiStateTaggingGenerator` | Runs its default generator |
| `BSBoneSwitchGenerator` | Default generator only, per-bone children ignored; tallied partial |
| `BSCyclicBlendTransitionGenerator` | Wrapped blender only; tallied partial |
| `BSOffsetAnimationGenerator` | Default generator only, offset clip ignored; tallied partial |
| `BSSynchronizedClipGenerator` | Wrapped clip, phase-synchronized; marker alignment tallied |
| `hkbBehaviorReferenceGenerator` | Reference pose; tallies `unresolvedBehaviorReference` |
| anything else | Reference pose; named in `unevaluatedGenerators` |

## State machines

A machine holds one current state and at most one transition in flight.
`BehaviorMachineState` is deliberately not `BehaviorNodeState`: it outlives deactivation,
because `m_startStateMode` 2 re-enters whatever was current when the machine stopped, and
121 of the 1,963 machines in the vanilla player graph are authored that way.

Entering picks the start state in this order, first match wins:

1. The state id a transition named through `FLAG_TO_NESTED_STATE_ID_IS_VALID`, which is how
   a parent machine drops the machine nested under its destination state into a particular
   state rather than into that machine's own start state.
2. `m_startStateMode` 2's remembered id.
3. `m_startStateMode` 1's read from the variable at `m_syncVariableIndex`.
4. `m_startStateId`, honouring a binding on `startStateId` — the vanilla data leans on that
   binding heavily.

Entering raises the state's `m_enterNotifyEvents` and the machine's
`m_eventToSendWhenStateOrTransitionChanges`. Leaving raises `m_exitNotifyEvents`, and so
does deactivation: a machine that stops being reached leaves the state it was in.

Nesting is ordinary recursion. A state whose generator is another `hkbStateMachine` runs it
through the same path, and `BehaviorGraphInstance.activeStates` publishes every machine the
last update reached, in walk order, outermost first — machine name, state name, and the
crossfade weight. That readout is what the real-data test asserts a state path against and
what items 14.5 and 14.6 read.

`hkbBehaviorReferenceGenerator` still produces the reference pose and tallies
`unresolvedBehaviorReference`: resolving a named behavior file into a second loaded graph
needs the multi-file loader item 14.5 brings.

## Transitions

Candidates come from two places: the current state's own
`hkbStateMachineTransitionInfoArray`, then the machine's `m_wildcardTransitions`, which
apply from any state. A candidate fires when all of these hold:

* `FLAG_DISABLED` is clear.
* Its `m_eventId` is in the active event set — so an event raised during an update moves
  the machine on the *next* one, in step with the rest of the update order.
* Its `m_toStateId` names an enabled state, and either differs from the current state or
  carries `FLAG_ALLOW_SELF_TRANSITION_BY_TRANSITION_INFO`.
* Its trigger and initiate intervals, if `FLAG_USE_TRIGGER_INTERVAL` or
  `FLAG_USE_INITIATE_INTERVAL` asks for them, are open. A window opens when its
  `m_enterEventId` is raised and closes when its `m_exitEventId` is; the time bounds are
  zero on every transition in the vanilla player graph, so a non-zero one is tallied.
* Its condition holds — see [Transition conditions](#transition-conditions).

Of the eligible candidates, the winner is the one with the highest `m_priority`; at equal
priority a state's own transition beats a wildcard; at equal priority and kind, array order
wins. **Havok's own tie-break is not documented in any source consulted here, so this
ordering is a decision**, made because a total order is what keeps two instances stepping
identically.

The state change happens when the transition *starts*: `currentStateId` becomes the
destination, exit and enter events fire, and the effect only fades the outgoing pose away.
That is why `FLAG_DELAY_STATE_CHANGE` exists as a separate authored flag — the default is
not delayed. It is set on 14 of the 3,769 transitions in the vanilla player graph and is
tallied rather than honoured.

An event arriving while a transition is still blending starts a new transition from
wherever the machine has got to, and the older blend is dropped rather than nested inside
the new one; each drop costs one `stateMachineTransitionInterrupted` entry. A transition
carrying `FLAG_UNINTERRUPTIBLE_WHILE_PLAYING` or `FLAG_UNINTERRUPTIBLE_WHILE_BLENDING`
refuses the new candidate outright.

The four machine-level event ids are checked only when no transition-info candidate fired.
`m_returnToPreviousStateEventId` goes back one state,
`m_transitionToNextHigherStateEventId` and `m_transitionToNextLowerStateEventId` step
through the sorted state ids honouring `m_wrapAroundStateId`, and
`m_randomTransitionEventId` picks the enabled state with the highest `m_probability`, ties
broken by the lowest id, and tallies `stateMachineRandomTransitionFixed` — an engine that
decides animation from an unseeded random source cannot be stepped twice with the same
result. Of 530 machines in the two `mt_behavior` files, four name a random-transition event
and none name the other three.

### The flag map, and how it was checked

`hkbStateMachineTransitionInfo::TransitionFlags` comes from the same open-source lineage as
the byte layouts (see [Havok behavior scope](/decisions/havok-behavior-scope.md)), and
every bit acted on was then confirmed against the local install rather than taken on faith:

| Bit | Name | Evidence in the vanilla player graph |
| --- | --- | --- |
| `0x1` | `USE_TRIGGER_INTERVAL` | 24 uses |
| `0x2` | `USE_INITIATE_INTERVAL` | 144 uses, each with an event pair |
| `0x4` | `UNINTERRUPTIBLE_WHILE_PLAYING` | 70 uses |
| `0x8` | `UNINTERRUPTIBLE_WHILE_BLENDING` | never set |
| `0x10` | `DELAY_STATE_CHANGE` | 14 uses |
| `0x20` | `DISABLED` | 2 uses |
| `0x100` | `DISABLE_CONDITION` | 3,340 uses, on exactly the transitions with a null `m_condition` |
| `0x200` | `ALLOW_SELF_TRANSITION` | 75 uses |
| `0x400` | `IS_GLOBAL_WILDCARD` | 729 uses, only inside wildcard arrays |
| `0x800` | `IS_LOCAL_WILDCARD` | 1,167 uses, only inside wildcard arrays |
| `0x1000` | `FROM_NESTED_STATE_ID_IS_VALID` | 24 uses; tallied, not acted on |
| `0x2000` | `TO_NESTED_STATE_ID_IS_VALID` | 642 uses, only where the id names a nested state |

`0x40`, `0x80`, and `0x4000` are never set. The `0x100` correlation is the strongest single
piece of evidence in the table: a bit that is set on every transition without a condition
object and clear on every transition with one is not plausibly anything but
"do not evaluate the condition".

## Transition conditions

`hkbExpressionCondition` and `hkbStringCondition` carry their test as authored text; Havok
compiles it at load into a `SERIALIZE_IGNORED` member, so the packfile holds the source and
nothing else. The grammar was recovered from the strings the vanilla files carry — 429 of
the 3,769 transitions name a condition, and every one of them fits:

```text
or         := and ( "||" and )*
and        := comparison ( "&&" comparison )*
comparison := unary ( ( "==" | "!=" | ">=" | "<=" | ">" | "<" ) unary )?
unary      := "!" unary | primary
primary    := number | variable | "(" or ")"
```

Observed forms include `IsFirstPerson == 0`,
`(IsNPC == 0) && (iLeftHandType != 7) && (iLeftHandType != 12)`,
`(iWantBlock == 0) || (iLeftHandType == 7)`, `!bIsSynced && !bIsRiding`,
`Speed >= fMinSpeed` (variable against variable), and
`(staggerDirection < .25) || (staggerDirection > .75)` (leading-dot literal). There are no
string literals, no arithmetic, no function calls, and no assignment.

Every value is a float and a bare variable is true when it is non-zero, which is how
`!bBlendOutSlow` reads. A string that does not parse, or one that names a variable the
graph does not declare, **blocks the transition** and is tallied
(`transitionConditionUnparsed`, `transitionConditionUnresolved`). Blocking rather than
defaulting is the choice that fails visibly: a wrong answer here fires a wrong transition,
and an animation that does not start reads as a bug where an animation that starts wrongly
reads as engine behaviour.

## Crossfades

`hkbBlendingTransitionEffect` fades the outgoing state's pose into the incoming one over
`m_duration`, shaped by `hkbBlendCurveUtils::BlendCurve`. The vanilla player graph uses two
curves — 389 smooth against 8 linear — so those are the two with a formula here: smooth is
`3t^2 - 2t^3`, linear is `t`. Any other curve falls back to smooth and is tallied, because
writing a formula for a curve no authored file uses would be inventing it.

A null `m_transition` pointer and a zero `m_duration` both mean an instant cut; 198 of the
397 blending effects in the vanilla player graph carry a zero duration. The clock runs
after selection, so a transition that starts on an update already shows one step of its
crossfade, and one that reaches its duration is dropped rather than posed at a weight of
exactly 1.

Of the `FlagBits`, only the sync bit is acted on (see
[Clip synchronization](#clip-synchronization)). The others say how root motion crosses the
blend, which item 14.5 owns once a character controller exists to disagree with it.

## Clip synchronization

Two mechanisms feed one seam, `BehaviorGraphInstance.pendingClipPhase`, which clip
evaluation reads after it has advanced local time.

A `hkbBlenderGenerator` whose `m_indexOfSyncMasterChild` names a child publishes that
child's playback phase — local time as a fraction of its own clip window — onto every other
child, every update. That is what stops a walk clip and a run clip of different lengths
from drifting apart as the blend weight moves between them: a 2-second master at phase 0.3
holds a 4-second follower at 1.2 seconds. The master is evaluated before its siblings so
its phase is current when they read it, and its result is slotted back at its own index so
the blend still folds in declared order. 28 blenders in the vanilla player graph name one.

A `hkbBlendingTransitionEffect` with the sync bit set publishes the outgoing state's phase
onto the incoming one, seed-only: applied when the incoming clip activates and never again,
because a destination clip permanently welded to the state it came from would never advance
on its own.

A clip forced onto another clip's phase reports no root motion for that update. It did not
walk there, so the difference between the two samples is not travel the character made.

`BSSynchronizedClipGenerator` runs the clip it wraps and takes part in phase
synchronization like any other clip, because the wrapped generator is an ordinary
`hkbClipGenerator`. What is still owed is the half that needs a second character:
`m_SyncAnimPrefix` names the partner's half of a paired animation and `m_fGetToMarkTime`
says how long this character has to reach the shared marker. Every evaluation costs one
`synchronizedClipMarkerIgnored` entry rather than an invented alignment.

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
* **Transition selection order is a decision.** Priority, then own-before-wildcard, then
  array order. Havok's tie-break is undocumented in the sources consulted; a total order is
  what makes two instances agree.
* **An interrupted crossfade is dropped, not nested.** Havok's own model allows transition
  effects to stack. Here the new transition blends from the state the machine had already
  switched to, so an interruption can pop by whatever fraction of the old blend was still
  running. Each one is tallied, so the probe says how often it happens.
* **A state machine does not write its current state back to `m_syncVariableIndex`.**
  `m_startStateMode` 1 reads the variable, and in the vanilla data that variable is an
  engine input — writing it back would clobber the input on the next update. Whether Havok
  keeps the variable synced in both directions is not settled by any source consulted here.
* **The transition-effect flag bits other than sync are not acted on.** The local decode
  reads bit 0 as ignore-from-generator, bit 2 as ignore-world-from-model, and bit 3 as
  ignore-to-generator, but that reading is not confirmed against an independent source and
  every one of them changes how root motion crosses a blend. Item 14.5 owns that question.

## Verification

Unit tests, all synthetic and all in code: `BehaviorStateMachineTests` (transition on
event, an event no transition names, wildcard transitions, priority and own-before-wildcard
tie-breaks, self-transition refusal, disabled transitions, condition gating, the smooth and
linear crossfade curves against hand-computed values, instant cuts, interruption and
uninterruptibility, exit-then-enter event order, start-state mode 2),
`BehaviorStateMachineNestingTests` (a nested machine's own start state, a transition naming
the nested start state, outer-before-inner enter order, exit events on deactivation,
loop-phase sync of a 2-second and a 4-second clip, and two nested instances stepped through
a transition producing identical poses, state paths, and event logs),
`BehaviorConditionExpressionTests` (the grammar, operator precedence, leading-dot literals,
unknown variables, and the text the grammar refuses), `BehaviorPoseMathTests` (blends against
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

The second env-gated test is
`make realtest T='BehaviorStateMachineRealDataTests/walksThePlayerLocomotionStatePath()'`.
It loads `mt_behavior.hkx`, steps it, and raises the locomotion events the file itself
declares, asserting the state path by the names the file declares:
`MT_Default_Behavior` sits in `MT_Standing_State`; `moveStart` moves it to
`MT_LocomotionType_State` and brings `MT_Locomotion_Behavior` — two levels of nesting
below — into reach; `moveStop` returns it and takes that machine back out; `SneakStart` and
`SneakStop` swing `MTIdleTurnTypeBehavior` between `MTIdleTurnState` and
`SneakIdleTurnState`. It pins the tally against the documented gap list, so a new gap name
fails the test until it is written down here. The report goes to gitignored
`logs/behavior-state-path.log`.

Run on 2026-08-03 against the local install: 35 graphs, 37,620 generator evaluations,
5,880 modifier evaluations, 2,651 events fired, 82 clips loaded, zero clip lookups missed,
zero undecodable objects, zero unevaluated generator classes. The ranked gaps were
`blenderParametricAsWeights` 4,560, `blenderBoneWeights` 1,200,
`unresolvedBehaviorReference` 480, `BSEventOnFalseToTrueModifier` 960,
`hkbEvaluateExpressionModifier` 840, `BSIsActiveModifier` 720,
`BSCyclicBlendTransitionGenerator` 480, `stateMachineNoStartState` 4. That list is the
worklist for items 14.5 and 14.6. The 8,880 `stateMachineStartStateOnly` entries item 14.3
reported are gone: every machine now runs its transitions, and stepping the graphs with no
input produces the same generator count it did before, because with no events raised there
is nothing to transition to.
