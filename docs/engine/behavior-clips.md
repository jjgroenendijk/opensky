---
type: Subsystem
title: Behavior clips and blending
description: How a behavior graph plays a clip, fires triggers and animation annotations, keeps
  clips in phase, blends poses per bone, and runs another behavior file through a reference.
tags: [engine, animation, havok, hkx, behavior]
---

# Behavior clips and blending

This page covers the pose side of the [behavior graph runtime](/engine/behavior-runtime.md): clips,
their events, and how poses mix. The clip data itself is on the
[hka animation](/formats/hka-animation.md) page.

## Clips

The clip window is the part of the animation a generator plays: `m_cropStartAmountLocalTime` is
cut from the front and `m_cropEndAmountLocalTime` from the back. Every time below is measured inside
that window.

- Local time advances by `deltaTime * m_playbackSpeed`. When `m_enforcedDuration` is positive, it
  is also multiplied by `window / m_enforcedDuration`.
- `m_startTime` places a clip that just became active.
- `m_mode` 0 stops at the window end. Mode 1 loops. Mode 2 reads `m_userControlledTimeFraction`.
  Mode 3, ping-pong, runs as a loop and is counted.
- Sampling goes through the spline animation decoder, behind a clip interface, so the runtime does
  not care who loads the bytes.

## Clip triggers and annotations

A clip tells the rest of the graph where it is with events. They come from two places.

`hkbClipTriggerArray` holds the authored triggers. A trigger fires when the update steps over it,
on the half-open interval `(previous, current]`. `m_acyclic` fires on the first cycle only.
Clip-done events are triggers, not a separate mechanism.

The animation's own `hkaAnnotationTrack`s are the second source. They are not the same thing,
even though the `m_isAnnotation` flag suggests it. Skyrim's movement clip generators have an empty
`m_triggers`. `FootLeft` and `FootRight` are annotations inside `mt_walkforward.hkx` and its
siblings, at 0.2333 s and 0.8 s of a walk cycle
([byte layout](/formats/hka-animation.md#m_annotationtracks)). A runtime that reads only the
trigger array walks in silence ([footstep sounds](/engine/footstep-sounds.md)).

Both sources use the same crossing test. An annotation is a mark on the animation, not on the
generator, so:

- it is always cyclic: it comes round on every loop;
- its time is measured in the animation, so the window start is subtracted before the test;
- an annotation outside the window was cut away and never fires.

A graph that declares no event by the annotation's name drops it quietly. This is not an error: one
animation is played by behavior files that care about different marks.

One exception to the half-open interval applies to annotations only. The update that starts a clip
covers the closed interval from its start time. Vanilla places marks on the first frame and means
them: `1HM_Equip.hkx` has `BeginWeaponDraw` at 0.0. Under the half-open rule such a mark could never
fire, and [melee combat](/engine/melee-combat.md) could not see a drawn weapon reach the hand. Later
updates stay half-open, so a mark is never fired twice.

`m_relativeToEndOfClip` applies to authored triggers only. It holds an offset from the end, not a
distance back from it, and vanilla writes it negative. Example: in `0_master.hkx`, the
`MT_JumpLand` clip places `JumpLandEnd` at `m_localTime` -0.8, meaning 0.8 s before the clip ends.
So the time is `window.length + m_localTime`. Subtracting put the trigger 0.8 s past the end, where
nothing crossed it. The root machine then entered `JumpLandState` on the first step off the ground
and never left, and every movement state below it was out of reach. A positive offset from the end
names a time outside the clip. It is refused, not folded back in, because firing it would fire an
event the author never placed.

## Clip synchronization

Two mechanisms keep clips in phase. Clip evaluation reads the phase after it advances local time.

A `hkbBlenderGenerator` whose `m_indexOfSyncMasterChild` names a child copies that child's phase
onto every other child, every update. Phase is local time as a fraction of the clip's window. This
stops a walk clip and a run clip of different lengths from drifting apart as the blend weight moves.
Example: a 2-second master at phase 0.3 holds a 4-second follower at 1.2 seconds. The master runs
first, so its phase is current when the others read it, and its result goes back at its own index,
so the blend still adds up in declared order. 28 blenders in the vanilla player graph name a master.

A `hkbBlendingTransitionEffect` with the sync bit set copies the old state's phase onto the new one
once, when the new clip starts. A new clip tied to the old state forever would never advance on its
own.

A clip forced onto another clip's phase reports no root motion for that update. It did not walk
there, so the difference between its samples is not travel.

`BSSynchronizedClipGenerator` plays its wrapped clip and takes part in phase sync like any clip,
because the wrapped generator is a plain `hkbClipGenerator`. The half that needs a second character
is still owed: `m_SyncAnimPrefix` names the partner's half of a paired animation, and
`m_fGetToMarkTime` says how long this character has to reach the shared marker. Each evaluation
counts one `synchronizedClipMarkerIgnored`.

## Blending

A pose has one bone transform per skeleton bone, starting from the reference pose. A clip gives only
the bones it animates. The full pose is what blending needs: two children that animate different
bones must still mix bone by bone, and a bone neither animates must come out as the reference pose.
The skeleton pose code composes the same way, so both agree on what a bone without animation is.

The blend adds children from left to right. After children of total weight W, the next child of
weight w enters at `w / (W + w)`. For two children of weights a and b that is exactly
`blend(first, second, weight: b / (a + b))`. For translation and scale the result is exactly the
weighted average.

- Translation and scale mix linearly.
- Rotation uses slerp on the shortest arc. So a turn from -10 to +10 degrees passes through 0, not
  180.
- A degenerate quaternion becomes the identity. Broken input must not produce a NaN pose.

A child with weight zero or less, or under `m_referencePoseWeightThreshold`, is dropped, not
normalized. So a blender whose weights all fall away gives the reference pose, not a divide by zero.

The pose blend uses `m_weight`. Root travel uses `m_worldFromModelWeight`, which exists so a child
can drive motion without driving the pose.

A child's `m_boneWeights` (`hkbBoneWeightArray`) scales its weight per bone. An upper-body layer
needs this. Skyrim's player graph blends a full-body movement pose with a left-arm pose and a
right-arm pose, and each arm child masks itself to its own arm. Without the mask, three unrelated
poses would be averaged over the whole skeleton. A mask shorter than the skeleton counts at full
weight past its end, not zero. Short masks are normal in mod data, and reading the rest as zero
would drop every bone the author did not reach.

## Behavior references

`0_master.hkx` is a shell. Its jump, movement, combat, and magic branches are
`hkbBehaviorReferenceGenerator` nodes. Each names another behavior file, such as `mt_behavior.hkx`
or `1hm_behavior.hkx`, one of the 18 files beside it. Every movement state the player has is behind
one of them.

A reference is resolved by name. The engine reads the file from the archives. A test uses a table
built in code. The referenced file becomes its own instance over its own decode, with the parent's
skeleton and clip source. It has its own variables, events, and node state, like Havok's
`hkbBehaviorGraph`.

The two instances are joined only by names:

- Variables pass from parent to child before every child update, for every name both declare. A
  name only the child declares keeps its own value: that is the sub-behavior's private state.
- Events pass both ways, once in each direction. The parent's active set is raised on the child
  before its update. What the child's own nodes raised during its update is raised on the parent,
  and seen on the parent's next update. The pull reads the child's waiting queue, not the active
  set its update returned, and the push skips names just pulled from that child.
- The child's active states are added after the parent's, so the published state path runs through
  the reference.
- A reference reached twice in one parent update runs once. Otherwise its clock would advance twice
  and run fast.
- A child that references one of its own parents is refused by name. Mod data can contain cycles.
  Refusing by name, not by depth, keeps a legal deep nesting working.

The event rule matters. The active set already holds everything the parent pushed in on the previous
update. Raising it back made every crossing event bounce between the graphs forever. The vanilla
player graph re-fired `moveStart` and `IdleStop` on all 120 steps of a walked second, which filled
the bounded event queue and pushed the real footstep tags out.

Lookup uses the file name alone, ignoring case, in the folder the root file came from. So the
first-person set under `meshes\actors\character\_1stperson\behaviors\` and the third-person set
stay apart without either being named. A name no source can supply counts one
`unresolvedBehaviorReference`.
