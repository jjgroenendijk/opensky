---
type: File Format
title: HKX Behavior Node Classes
description: Byte layouts of the Havok behavior node classes in vanilla Skyrim SE behavior
  files (shared headers, state machines, generators, transitions, conditions) and how a graph
  is walked.
tags: [format, havok, hkx, behavior, animation, locomotion]
---

# HKX behavior node classes

The [behavior graph objects](/formats/hkx-behavior.md) page stops at the graph's root
generator. This page covers the node tree below it. Modifiers and Bethesda's own classes are
on the [behavior modifier classes](/formats/hkx-behavior-modifiers.md) page. Together the two
pages cover every class in the vanilla player behavior files. The runtime is on the
[behavior runtime](/engine/behavior-runtime.md) page.

`openskycli hkx <key>` prints a file's decoded nodes ([CLI](/tools/cli.md)).

## Sources

There is no public Havok specification. Member offsets come from open-source projects and were
checked byte by byte against the local SSE install.

- ret2end/HKX2Library (MIT): an SSE packfile reader and writer, and the only one of the three
  that has Bethesda's `BS*` classes. Its offset tables are the main source. Its class
  signatures match the vanilla class-name tables exactly.
- soulsmods/DSMapStudio HKX2 (MIT): a second reimplementation of the stock classes, used as a
  cross-check.
- exyorha/hkxparse (MIT): container structures.

No Havok SDK, leaked source, Creation Kit internals, or SKSE internals were used. See
[Havok behavior scope](/decisions/havok-behavior-scope.md).

## How the offsets were confirmed

Every vanilla behavior file under `meshes\actors\character\` decodes with no object left
undecoded and no failure. The only unresolved fields are `noFixup`, which is a normal null
pointer. There is no `outOfBounds`, `sectionMissing`, `negativeCount`, or `undecodableString`
anywhere. A wrong offset would produce one of those.

A graph walk from the root generator reaches every object except exactly five: the root
container, the behavior graph, its data, its string data, and its variable value set. Those
five sit above the node tree. So the walk misses nothing.

The walk follows every pointer, and the first visit wins. A graph is not a tree: many nodes can
share one transition effect or bone weight array.

## Shared headers

Sizes of pointers, arrays, and strings are on the [behavior graph](/formats/hkx-behavior.md)
page. All offsets here are full in-memory offsets.

Almost every class comes from one of three bases:

`hkbBindable` (48 bytes):

| Offset | Field | Type | Notes |
| --- | --- | --- | --- |
| 0x10 | `m_variableBindingSet` | pointer | The graph variables bound into this object |
| 0x18 | `m_cachedBindables` | `hkArray` | `SERIALIZE_IGNORED` |
| 0x28 | `m_areBindablesCached` | `hkBool` | `SERIALIZE_IGNORED` |

`hkbNode` (72 bytes) adds:

| Offset | Field | Type |
| --- | --- | --- |
| 0x30 | `m_userData` | uint64 |
| 0x38 | `m_name` | `hkStringPtr` |
| 0x40 | `m_id`, `m_cloneState`, `m_padNode` | `SERIALIZE_IGNORED` |

`hkbGenerator` (72 bytes) adds nothing. `hkbModifier` (80 bytes) adds `m_enable` (`hkBool`) at
0x48 and a pad at 0x49.

The most useful rule: a generator's own members start at 0x48, and a modifier's at 0x50.

Two inline structs repeat:

- `hkbEventProperty` (same as `hkbEventBase`), 16 bytes: int32 `m_id` at 0x00, pointer
  `m_payload` at 0x08. `m_id` indexes the graph's event list. -1 means no event.
- `hkVector4` and `hkQuaternion`, 16 bytes: four floats, 16-byte aligned.

## State machine classes

`hkbStateMachine` (264 bytes) comes from `hkbGenerator`. The root generator of every vanilla
behavior file is a state machine.

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x48 | `m_eventToSendWhenStateOrTransitionChanges` | `hkbEvent` | 16 bytes |
| 0x60 | `m_startStateChooser` | pointer | null in every vanilla player file |
| 0x68 | `m_startStateId` | `i32` | a state *id*, not an index |
| 0x6C | `m_returnToPreviousStateEventId` | `i32` | |
| 0x70 | `m_randomTransitionEventId` | `i32` | |
| 0x74 | `m_transitionToNextHigherStateEventId` | `i32` | |
| 0x78 | `m_transitionToNextLowerStateEventId` | `i32` | |
| 0x7C | `m_syncVariableIndex` | `i32` | variable holding the current state |
| 0x80 | `m_currentStateId` | `i32` | `SERIALIZE_IGNORED` |
| 0x84 | `m_wrapAroundStateId` | `hkBool` | |
| 0x85 | `m_maxSimultaneousTransitions` | `i8` | |
| 0x86 | `m_startStateMode` | `i8` enum | 0 use id, 1 sync from variable, 2 resume |
| 0x87 | `m_selfTransitionMode` | `i8` enum | |
| 0x90 | `m_states` | `hkArray<hkbStateMachineStateInfo*>` | |
| 0xA0 | `m_wildcardTransitions` | pointer | transitions valid from any state |

`hkbStateMachineStateInfo` (120 bytes) comes from `hkbBindable`, not from `hkbNode`. So its
name is its own member at 0x60, not the inherited one at 0x38. This is the easiest offset in
this set to get wrong.

| off | field | type |
| --- | --- | --- |
| 0x30 | `m_listeners` | `hkArray<hkbStateListener*>` |
| 0x40 | `m_enterNotifyEvents` | pointer to `hkbStateMachineEventPropertyArray` |
| 0x48 | `m_exitNotifyEvents` | pointer to `hkbStateMachineEventPropertyArray` |
| 0x50 | `m_transitions` | pointer to `hkbStateMachineTransitionInfoArray` |
| 0x58 | `m_generator` | pointer to `hkbGenerator` |
| 0x60 | `m_name` | `hkStringPtr` |
| 0x68 | `m_stateId` | `i32` |
| 0x6C | `m_probability` | `hkReal` |
| 0x70 | `m_enable` | `hkBool` |

`hkbStateMachineTransitionInfoArray` and `hkbStateMachineEventPropertyArray`, both size 32,
are `hkReferencedObject` wrappers around one hkArray at 0x10 — of
`hkbStateMachineTransitionInfo` (stride 72) and of `hkbEventProperty` (stride 16).

`hkbStateMachineTransitionInfo`, 72 bytes:

| off | field | type |
| --- | --- | --- |
| 0x00 | `m_triggerInterval` | `hkbStateMachineTimeInterval`, 16 bytes |
| 0x10 | `m_initiateInterval` | `hkbStateMachineTimeInterval` |
| 0x20 | `m_transition` | pointer to `hkbTransitionEffect` |
| 0x28 | `m_condition` | pointer to `hkbCondition` |
| 0x30 | `m_eventId` | `i32` |
| 0x34 | `m_toStateId` | `i32` |
| 0x38 | `m_fromNestedStateId` | `i32` |
| 0x3C | `m_toNestedStateId` | `i32` |
| 0x40 | `m_priority` | `i16` |
| 0x42 | `m_flags` | `i16` flags |

`hkbStateMachineTimeInterval`, 16 bytes: `i32 m_enterEventId`, `i32 m_exitEventId`,
`hkReal m_enterTime`, `hkReal m_exitTime`.

## Generator classes

`hkbClipGenerator` (272 bytes) is a leaf node. It is the only class that names an animation.

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x48 | `m_animationName` | `hkStringPtr` | as the character file spells it |
| 0x50 | `m_triggers` | pointer to `hkbClipTriggerArray` | |
| 0x58 | `m_cropStartAmountLocalTime` | `hkReal` | |
| 0x5C | `m_cropEndAmountLocalTime` | `hkReal` | |
| 0x60 | `m_startTime` | `hkReal` | |
| 0x64 | `m_playbackSpeed` | `hkReal` | |
| 0x68 | `m_enforcedDuration` | `hkReal` | |
| 0x6C | `m_userControlledTimeFraction` | `hkReal` | |
| 0x70 | `m_animationBindingIndex` | `i16` | index into the character animation list |
| 0x72 | `m_mode` | `i8` enum | 0 single, 1 loop, 2 user controlled, 3 ping pong |
| 0x73 | `m_flags` | `i8` bit set | 1 continue motion, 2 sync half cycle, 4 mirror |

`hkbClipTriggerArray`, size 32: `m_triggers` at 0x10, `hkbClipTrigger` stride 32 —
`hkReal m_localTime` at 0x00, `hkbEventProperty m_event` at 0x08, then `hkBool`
`m_relativeToEndOfClip`, `m_acyclic`, `m_isAnnotation` at 0x18, 0x19, 0x1A.

`hkbBlenderGenerator` (160 bytes) runs several children at once and mixes their poses.

| off | field | type |
| --- | --- | --- |
| 0x48 | `m_referencePoseWeightThreshold` | `hkReal` |
| 0x4C | `m_blendParameter` | `hkReal` |
| 0x50 | `m_minCyclicBlendParameter` | `hkReal` |
| 0x54 | `m_maxCyclicBlendParameter` | `hkReal` |
| 0x58 | `m_indexOfSyncMasterChild` | `i16` |
| 0x5A | `m_flags` | `i16` bit set |
| 0x5C | `m_subtractLastChild` | `hkBool` |
| 0x60 | `m_children` | `hkArray<hkbBlenderGeneratorChild*>` |

`hkbBlenderGeneratorChild`, size 80, derives `hkbBindable`: `m_generator` at 0x30,
`m_boneWeights` at 0x38, `hkReal m_weight` at 0x40, `hkReal m_worldFromModelWeight` at
0x44.

`hkbPoseMatchingGenerator`, size 240, derives `hkbBlenderGenerator`, so the blender members
above come first and its own start at 0xA0: `hkQuaternion m_worldFromModelRotation` 0xA0,
`m_blendSpeed` 0xB0, `m_minSpeedToSwitch` 0xB4, `m_minSwitchTimeNoError` 0xB8,
`m_minSwitchTimeFullError` 0xBC, `i32 m_startPlayingEventId` 0xC0,
`i32 m_startMatchingEventId` 0xC4, `i16` bone indices at 0xC8, 0xCA, 0xCC, 0xCE, and
`i8 m_mode` at 0xD0.

Three smaller generators:

| class | size | members |
| --- | --- | --- |
| `hkbManualSelectorGenerator` | 96 | `m_generators` `hkArray<hkbGenerator*>` 0x48, `i8 m_selectedGeneratorIndex` 0x58, `i8 m_currentGeneratorIndex` 0x59 |
| `hkbModifierGenerator` | 88 | `m_modifier` 0x48, `m_generator` 0x50 |
| `hkbBehaviorReferenceGenerator` | 88 | `m_behaviorName` `hkStringPtr` 0x48 |

`hkbBehaviorReferenceGenerator` is how `0_Master.hkb` pulls in the behavior file of each
activity. It names the file. It does not point at an object.
