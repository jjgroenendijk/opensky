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

## Bindings

A `hkbVariableBindingSet` maps a member path on a node to a variable index. Writing a graph variable
changes a node field. Bindings are applied just before the node runs and are never cached across
nodes. The binding at `m_indexOfBindingToEnable` becomes the node's enable flag.

Member paths in the vanilla files have no `m_` prefix: `blendParameter`, `startStateId`,
`selectedGeneratorIndex`, `isActive`, `weight`, `fBlendParameter`, `currentStateId`,
`fOffsetVariable`. The decoders name fields after the Havok members, which do have it. So a leading
`m_` is removed from both sides before lookup. This was measured: an early version resolved every
binding and then looked each one up under the wrong key.

A binding that cannot be applied is counted, not guessed. Examples: a character property, a
variable index out of range, a bit index past 32, or an empty path that binds the whole object.

## Generators

| Class | What it does |
| --- | --- |
| `hkbClipGenerator` | Plays a clip ([clips](/engine/behavior-clips.md)) |
| `hkbBlenderGenerator` | Weighted blend of every child, masked per bone ([blending](/engine/behavior-clips.md)) |
| `hkbManualSelectorGenerator` | Runs the child at `selectedGeneratorIndex`. Out of range gives the reference pose |
| `hkbModifierGenerator` | Runs its child, then its modifier over the result |
| `hkbPoseMatchingGenerator` | Runs as its blender base, and is counted |
| `hkbStateMachine` | See [state machines](/engine/behavior-state-machines.md) |
| `BSiStateTaggingGenerator` | Runs its default generator |
| `BSBoneSwitchGenerator` | Default generator only. Per-bone children are ignored and counted |
| `BSCyclicBlendTransitionGenerator` | The wrapped blender only, counted |
| `BSOffsetAnimationGenerator` | Default generator only. The offset clip is ignored and counted |
| `BSSynchronizedClipGenerator` | The wrapped clip, phase-synchronized. Marker alignment is counted |
| `hkbBehaviorReferenceGenerator` | Runs another behavior file ([behavior references](/engine/behavior-clips.md)) |
| Anything else | The reference pose, and the class is named in the tally |

## Modifiers

These modifiers run:

- `hkbModifierList`: its children, in order.
- `hkbEventDrivenModifier`: `m_activateEventId`, `m_deactivateEventId`, and `m_activeByDefault`
  turn the wrapped modifier on and off.
- `hkbTimerModifier`: raises `m_alarmEvent` once, after `m_alarmTimeSeconds`.
- `BSEventOnDeactivateModifier`: raises its event on deactivation.
- `BSEventEveryNEventsModifier`: counts `m_eventToCheckFor` and raises `m_eventToSend` every N.

Every other modifier passes its input through and is named in the tally. This is not a hidden
approximation. A missing foot correction looks like a foot that does not plant, which is visibly
wrong. An invented correction would look plausible and be wrong.

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

Buckets: `unevaluatedGenerators`, `partialGenerators`, `passthroughModifiers`, `unresolvedClips`,
`unappliedBindings`, `undecodableObjects`, and `featureGaps`. The positive side is
`boundMemberPaths` (which member paths the data drives), and the volume counters
`generatorsEvaluated`, `modifiersEvaluated`, and `updatesRun`.

## Choices made without a source

These are guesses, marked as guesses:

- Blender flags are not used. `HKBBlenderFields.flags` is decoded, and local decode notes read bit
  0 as cycle sync and bit 2 as parametric blend. No independent source confirms that. So the
  authored `m_weight` values are used as weights directly, and each such blender counts one
  `blenderParametricAsWeights`. `blendParameter` is the most-bound member in the vanilla player
  graph, so a parametric blend is the largest piece of locomotion still owed.
- Root motion is the difference of two samples of the root bone, in its own local frame. Vanilla
  data has no root motion to measure ([walk mode](/engine/walk-mode.md)), so the extracted motion
  class is not decoded.
- The root bone is bone 0, which is `NPC Root [Root]` in every vanilla rig. The index can be
  configured, but nothing reads it from the character file yet.
- `BSEventEveryNEventsModifier.m_randomizeNumberOfEvents` uses its maximum, not a random count. A
  graph that decides timing from an unseeded random source cannot be stepped the same way twice.
  The choice is counted.
- A state machine does not write its current state back to `m_syncVariableIndex`. In vanilla data
  that variable is an engine input, and writing it back would overwrite the input on the next
  update. No source says whether Havok syncs it both ways.
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
