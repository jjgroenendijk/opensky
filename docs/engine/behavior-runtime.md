---
type: Subsystem
title: Behavior graph runtime
description: Running a decoded Havok Behavior graph with no renderer - the instance model, the
  fixed update order, variables, events, bindings, generators, modifiers, the output contract,
  the coverage tally, and the choices made where no source says what Havok does.
tags: [engine, animation, havok, hkx, behavior, locomotion]
---

# Behavior graph runtime

A behavior graph is Havok's animation state machine. The decoded objects are on the
[HKX behavior graph objects](/formats/hkx-behavior.md) and
[HKX behavior nodes](/formats/hkx-behavior-nodes.md) pages. The runtime makes them run: variables,
events, bindings, clips, blends, and state machines, stepped with no renderer and in a fixed order,
so two runs with the same input give the same result.

Related pages:

- [Behavior state machines](/engine/behavior-state-machines.md): states, transitions, conditions,
  and crossfades.
- [Behavior clips and blending](/engine/behavior-clips.md): clip time, triggers, synchronization,
  pose blending, and behavior references.
- [Locomotion graph](/engine/locomotion-graph.md): the variables and events the player's movement
  writes.
- [First person](/engine/first-person.md): the second graph that drives the arms.

The code lives in `Sources/OpenSkyBehavior/`, apart from the format parsers in
`Sources/OpenSkyFormatsAnimation/HKX/`. Decoding a file and running a graph are different jobs, and
they fail in different ways.

## Instance model

One instance is one running graph. It holds a root generator, the graph data, a source that finds a
decoded object by its pointer target, a skeleton, and a clip source.

Nothing is global. Two instances over the same decoded file share the read-only decode and nothing
else: no variables, no events, and no node state. The first-person graph runs beside the
third-person one this way.

The engine's object source decodes on demand. A test gives a table of decoded values built in code.
So the runtime's tests need no packfile bytes. The byte layouts are covered by the decode tests.

In the game, the player's clip source reads clips on the shared play-time worker. A clip it has not
read yet is "loading", not missing. An update that reaches a loading clip still runs its state
machines and events, but returns the last pose in which every clip was ready, with no root motion.
When the graph is built, it asks the source to prefetch the clips its start states reach. Those are
the clip generators below each state machine's start state, through behavior references too.

The state of each node (clip time, cycle count, timer, running flag) is keyed by the node's pointer
target, not by its path in the tree. A behavior graph shares nodes: one bone weight array or one
transition effect can have many parents. Havok keys node state the same way.

## Update order

One update always runs these steps:

1. Every event raised since the last update becomes the active event set. An event raised during
   this update is not visible to it.
2. The generator tree is walked depth first from the root, with children in the order the class
   declares them. A node's bindings are applied just before it runs.
3. Nodes reached last update but not this one are deactivated, in packfile order (section, then
   offset).
4. The active event set closes and is returned.

Step 1 is a choice, not an observation: no source consulted says when Havok makes a mid-update event
visible. Deferring to the next update makes the result independent of the order of the walk. For
example, an event raised by a clip trigger deep in the tree cannot reach a modifier that already
ran. Step 3 uses packfile order for the same reason: a set read in hash order would fire
deactivation events in a different order on every run.

A node becomes active the first update it is reached, and inactive the first update it is not. A
depth limit of 64 stops a cyclic graph and is counted, not recursed into.

## Variables

Variables are seeded from `hkbBehaviorGraphData`: the type from `m_variableInfos`, the name from
`m_stringData.m_variableNames`, and the start value from `m_variableInitialValues`. Bool, int, and
real use the word list. A real is its float bit pattern stored in an `i32`. Vector and quaternion
use the quad list.

Words are stored as raw `i32` values, so a round trip is exact, and a declared type the runtime does
not know still reads and writes without loss. Reads and writes convert to the declared type instead
of failing. A binding names a member whose type is fixed, but the author chose the variable's type.
Callers use names. `hkbVariableBindingSet` uses indexes. Both work.

## Events

Events are also positional: index, name, and flags. A raised event waits for the next update. The
waiting queue holds at most 256 and drops the oldest first. So a modifier that raises an event every
update, with nothing reading it, cannot grow the queue without end.

A name, of an event or a variable, matches without case. The game shows this: the vanilla
`trapbase` script raises `loop` and `reset` on the swinging blade graph, which declares `Loop` and
`Reset`, and the blade swings.

## Bindings

A `hkbVariableBindingSet` maps a member path on a node to a variable index. Writing a graph variable
changes a node field. Bindings are applied just before the node runs and are never cached across
nodes. The binding at `m_indexOfBindingToEnable` becomes the node's enable flag.

Member paths in the vanilla files have no `m_` prefix: `blendParameter`, `startStateId`,
`selectedGeneratorIndex`, `isActive`, `weight`, `fBlendParameter`, `currentStateId`,
`fOffsetVariable`. The decoders name fields after the Havok members, which do have it. So a leading
`m_` is removed from both sides before lookup. This was measured: an early version resolved every
binding and then looked each one up under the wrong key.

Bindings also run the other way. A member that a modifier computes, such as
`BSIsActiveModifier.bIsActive0` or `BSInterpValueModifier.result`, is copied back to its bound
variable after the modifier runs. A bit-addressed binding sets or clears one bit. Without this,
a graph's own state flags never change.

A binding of type 1 reads a character property instead of a graph variable. The index names
a property in the graph's own list, and the value comes from the character file by that name
([character data](/formats/hkx-behavior.md#hkbcharacterdata-and-hkbcharacterstringdata)).
Most vanilla ones bind a blender child's or a bone switch's bone weights. A referenced graph
reads the same character's properties.

The enable binding applies only to modifiers. A disabled modifier leaves the pose as it is
and writes no bound outputs.

A binding that cannot be applied is counted, not guessed. Examples: a variable index out of
range, a bit index past 32, or an empty path that binds the whole object.

## Generators

| Class | What it does |
| --- | --- |
| `hkbClipGenerator` | Plays a clip ([clips](/engine/behavior-clips.md)) |
| `hkbBlenderGenerator` | Weighted or parametric blend of its children, masked per bone and optionally synced ([blending](/engine/behavior-clips.md)) |
| `hkbManualSelectorGenerator` | Runs the child at `selectedGeneratorIndex`. Out of range gives the reference pose |
| `hkbModifierGenerator` | Runs its child, then its modifier over the result |
| `hkbPoseMatchingGenerator` | Its blender, with weights it sets itself ([pose matching](#pose-matching)) |
| `hkbStateMachine` | See [state machines](/engine/behavior-state-machines.md) |
| `BSiStateTaggingGenerator` | Runs its default generator, and reports `m_iStateToSetAs` as the graph's `iState` tag. The highest `m_iPriority` wins ([actor state graph](/engine/actor-state-graph.md#drunk-actors)) |
| `BSBoneSwitchGenerator` | Default generator, with each child's pose replacing it on the bones its bone weights cover |
| `BSCyclicBlendTransitionGenerator` | Its blender, with `m_fBlendParameter` as the blender's parameter. `m_EventToFreezeBlendValue` holds the parameter. `m_EventToCrossBlend`, only while held or blending, frees it and crossfades from a copy of the held blender, which keeps running at the held parameter, over `m_fTransitionDuration` with `m_eBlendCurve`. A repeat during the crossfade mirrors its progress: elapsed `e` becomes `d - e` |
| `BSOffsetAnimationGenerator` | Default generator plus the additive offset clip at weight 1. `f` is where `m_fOffsetVariable` sits in the offset range, clamped, and 0 for an empty range. The clip plays at `D/(n-1) + (D - D/(n-1)) f` for duration `D` and `n` frames, and is sampled again only when that time reaches another frame and `f` changed. An offset clip that is not additive adds nothing |
| `hkbReferencePoseGenerator` | The reference pose |
| `BSSynchronizedClipGenerator` | The wrapped clip, phase-synchronized. Marker alignment is counted |
| `hkbBehaviorReferenceGenerator` | Runs another behavior file ([behavior references](/engine/behavior-clips.md)) |
| Anything else | The reference pose, and the class is named in the tally |

## Pose matching

`hkbPoseMatchingGenerator` picks the child whose start pose is closest to the live pose. The
get-up after a ragdoll uses it to choose between getting up from the back and from the front.

- Three bones, `m_rootBoneIndex`, `m_otherBoneIndex`, and `m_anotherBoneIndex`, span a frame:
  the first axis points from root to other, and the third is the normal of the plane with
  another. The indices are ragdoll bones. A ragdoll bone maps to the rig bone of the same name
  without its `Ragdoll_` prefix.
- Each child is sampled once at its start time, which gives its signature. The error of a child
  is `1 - |dot(live, signature)|`, and the lowest error is best. The first update picks the
  best at once.
- After that, the best child must stay best for `(1 - e) m_minSwitchTimeNoError +
  e m_minSwitchTimeFullError`, and the pelvis must move at `m_minSpeedToSwitch` or faster.
- The current child's weight rises by `m_blendSpeed` per second to 1, and the others fall to 0.
  While matching, the children stay at their start. `m_startPlayingEventId` lets them play, and
  `m_startMatchingEventId` matches again and restarts the current clip.
- The live pose is what the engine passes as the physics pose, or else the pose the graph showed
  last.

## Mirrored clips

A clip with flag 4 plays mirrored. The character file's `hkbMirroredSkeletonInfo` names each
bone's partner and the mirror axis; `defaultmale.hkx` has the axis (1, 0, 0). With `A` the 180
degree turn about the axis and `M` the model-space reference rotations, the frame change of bone
`b` is `I(b) = conj(M_b) A M_partner(b)`, snapped to the nearest of the 24 axis-aligned
rotations when the dot is 0.9 or more. `I(-1)` is `A`.

The sample of bone `k` goes to `b = partner(k)`: the rotation becomes
`I(parent(b)) q conj(I(b))` (`conj(I(parent(b)))` on the right for an additive clip), the
translation `-I(parent(b)) t`, and the scale stays. Root travel is mirrored with `I(-1)`. A
character file without the info plays the clip unmirrored, and that is counted.

## Clip travel

A clip whose `m_extractedMotion` is an `hkaDefaultAnimatedReferenceFrame` travels by that frame:
samples spread evenly over its duration, each a position and a heading about `m_up`, linear
between samples. Any other reference frame class is approximated from the root bone and
counted. A user-controlled clip sits at `m_cropStartAmountLocalTime` plus
`m_userControlledTimeFraction` of the cropped length; the fraction is clamped to 0 to 1, and
speed, time step, and looping do not apply. A playback speed between -0.001 and 0.001 becomes
0.001, or -0.001 when it is 0 or less.

## Modifiers

Event and timer modifiers:

- `hkbModifierList`: its children, in order.
- `hkbEventDrivenModifier`: `m_activateEventId`, `m_deactivateEventId`, and `m_activeByDefault`
  turn the wrapped modifier on and off.
- `hkbTimerModifier` raises `m_alarmEvent` once after `m_alarmTimeSeconds`. `BSTimerModifier`
  does the same, and again every alarm period when `resetAlarm` is set.
- `BSEventOnDeactivateModifier`: raises its event on deactivation.
- `BSEventEveryNEventsModifier`: counts `m_eventToCheckFor` and raises `m_eventToSend` every N.
- `BSEventOnFalseToTrueModifier`: each enabled slot raises its event when its bool rises.
- `hkbEventsFromRangeModifier`: the bands run from `m_lowerBound` through each `m_upperBound`.
  Mode 0 raises the band's event on entry, mode 1 on every update inside it.

Variable modifiers, which write their outputs back through the bindings:

- `hkbEvaluateExpressionModifier` runs each statement in order. `var = expr` assigns a variable.
  `event if cond` raises an event by event mode: 0 once, 1 every update the condition holds,
  2 when it turns true, 3 every update after it first held. The grammar has numbers, variables,
  `+ - * / %`, comparisons, `&& || !`, and the functions in `BehaviorExpressionFunctions`. An
  event name the graph does not declare, such as `SoundPlay.X`, goes to `unboundEvents`.
  A statement whose text does not parse, or that names an undeclared variable, does nothing that
  update, and the other statements still run. The game does the same: it compiles each statement
  once, and a statement that fails gives no result. One vanilla statement assigns the undeclared
  `State`, so it never writes anything in the game either.
- `BSIsActiveModifier`, `BSInterpValueModifier`, `hkbDampingModifier`, `BSSpeedSamplerModifier`,
  `BSDecomposeVectorModifier`, `BSGetTimeStepModifier`, `hkbTransformVectorModifier`,
  `BSIStateManagerModifier`, and `BSModifyOnceModifier`.

Bone modifiers work in model space: Havok's +Y forward, +X right, +Z up.

- `hkbTwistModifier` and `hkbRotateCharacterModifier`; the second turns the root motion.
- `BSLookAtModifier` turns the head bones, then the eye bones, towards the target, limited per
  bone and eased by the on and off gains. `BSDirectAtModifier` spreads a heading and pitch over
  its bone chain.
- `hkbFootIkModifier` moves each ankle by the difference between the probed ground and
  `m_originalGroundHeightMS`, with a two-bone solve from hip to ankle. Without a ground probe the
  ground is flat at that height, so the pose does not change.
- `BSLimbIKModifier` bends a chain back from geometry the ground probe reports.
- `BSTweenerModifier` and `BSPassByTargetTriggerModifier` read world positions from the
  character context the engine sets before each update.
- `hkbKeyframeBonesModifier`, `hkbGetUpModifier`, and `hkbFootIkControlsModifier` only hand
  data to physics, through `BehaviorPhysicsRequests`.

Any other modifier passes its input through and is named in the tally. A missing foot
correction looks like a foot that does not plant, which is visibly wrong. An invented
correction would look plausible and be wrong.

## Output

One update returns:

- `bones`: a local transform for every skeleton bone. The root bone stays at its reference pose.
- `rootMotion`: the root bone's travel this update, as translation and rotation. It is never
  applied to `bones`. A walk clip that bakes travel into the root would walk the whole skeleton
  away from the origin. The character controller decides where the character goes
  ([walk mode](/engine/walk-mode.md)). A clip that wraps inside an update reports the travel to the
  window end plus the travel from the window start, not the negative jump of a plain difference.
- `firedEvents`: every event the update saw, in raise order.
- `time`: seconds of graph time this instance has run.

## The tally

The tally counts what the runtime could not do, like the condition and ActionScript tallies. It has
counters per class and per feature, name tables with a size limit and totals without one, and it
never crashes on something missing. It answers "which Havok Behavior classes does OpenSky still owe
Skyrim?", and the real-data probe ranks it.

Buckets: `unevaluatedGenerators`, `passthroughModifiers`, `unresolvedClips`,
`unappliedBindings`, `undecodableObjects`, and `featureGaps`. The positive side is
`boundMemberPaths` (which member paths the data drives), and the volume counters
`generatorsEvaluated`, `modifiersEvaluated`, and `updatesRun`.

## Choices made without a source

These are guesses, marked as guesses:

- The parametric weights and the shared cycle of a synced blender follow the flag names and the
  runtime members in the class reflection data, not a description of Havok's maths
  ([parametric blend](/engine/behavior-clips.md#parametric-blend)). That only the
  leader of a synced blender raises annotations is also a choice; authored triggers still fire
  from every child.
- Without a reference frame, root motion is the difference of two samples of the root bone, in
  its own local frame ([walk mode](/engine/walk-mode.md)).
- The pose matching frame has its heading about up removed, so a ragdoll matches whichever way
  it faces. The source does not say whether Havok removes it. The pelvis speed is the live
  pelvis bone's travel per second, in model space.
- The pose matching mode at activation comes from `m_mode`: 0 matches, any other value plays.
- The root bone is bone 0, which is `NPC Root [Root]` in every vanilla rig. The index can be
  configured, but nothing reads it from the character file yet.
- `BSEventEveryNEventsModifier.m_randomizeNumberOfEvents` draws each N from a random source with
  a fixed seed, so two instances stepped the same way give the same events.
- Several Bethesda modifiers have no public description. Their behaviour is read from their
  member names and from how the vanilla graphs bind them: `BSIsActiveModifier` (true while
  running, false after), `BSInterpValueModifier` (moves by `gain` per second),
  `BSSpeedSamplerModifier` (passes `goalSpeed` to `speedOut`), `hkbDampingModifier` (one PID
  step per update), `BSTweenerModifier`, `BSLimbIKModifier`, and the aim axis conventions of the
  look-at and direct-at modifiers.
- A state machine writes its current state ID to `m_syncVariableIndex` when the index names a
  variable, so two machines that share it stay in step
  ([state machines](/engine/behavior-state-machines.md)). No source confirms that Havok writes
  it back.
- Transition effect flag bits other than sync are not used. Local decode notes read bit 0 as
  ignore-from-generator, bit 2 as ignore-world-from-model, and bit 3 as ignore-to-generator. No
  independent source confirms that, and each one changes how root motion crosses a blend.

The transition order and the crossfade interrupt rule are also choices, explained on the
[state machines](/engine/behavior-state-machines.md) page.

## Probing the install

The real-data probe builds one instance over each of the 35 vanilla player behavior files, third
person and `_1stperson`, loads their clips from the install, and steps each 60 times at 1/30 s with
no input. Every graph must decode fully, reach a generator and a state machine, and produce bones.
The ranked tally is the list of Havok semantics still owed. A second probe raises the locomotion
events `mt_behavior.hkx` declares and checks the state path by the names the file declares. For
example, `moveStart` moves `MT_Default_Behavior` from `MT_Standing_State` to
`MT_LocomotionType_State`, and brings `MT_Locomotion_Behavior`, two levels down, into reach.
