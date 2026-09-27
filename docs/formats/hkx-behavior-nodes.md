---
type: File Format
title: HKX Behavior Node Classes
description: Byte layouts of the Havok behavior node classes in vanilla Skyrim SE player
  behavior files - shared headers, state machines, generators, transitions, and conditions.
tags: [format, havok, hkx, behavior, animation, locomotion]
---

# HKX behavior node classes

[HKX behavior graph objects](/formats/hkx-behavior.md) covers the top of a behavior file
and stops at the graph's root generator. This page covers the node tree below it. Transitions,
conditions, modifiers, and Bethesda's own classes are in
[HKX behavior modifier classes](/formats/hkx-behavior-modifiers.md). Together the two
pages cover every class in the vanilla player behavior files, as the
[Havok behavior scope](/decisions/havok-behavior-scope.md) requires.

`openskycli hkx <key>` prints the decoded nodes of a file (see [CLI](/tools/cli.md)).

## References

There is no public Havok specification. Member offsets come from open projects and were
checked byte by byte against vanilla files:

- ret2end/HKX2Library (MIT): a Skyrim SE packfile reader and writer, and the only one of
  the three with Bethesda's `BS*` classes. Its member offset tables are the main source.
  Its class signatures match the vanilla class name tables exactly.
- soulsmods/DSMapStudio HKX2 (MIT): a separate version of the stock classes, for a
  cross-check.
- exyorha/hkxparse (MIT): packfile structures.

No Havok SDK headers, no leaked or decompiled source, and no Creation Kit or SKSE internals
were used.

## Shared headers

Sizes and rules are as in [HKX behavior graph objects](/formats/hkx-behavior.md). Every
offset is the offset in memory.

Almost every class comes from one of these bases, so their members sit at fixed offsets:

| Base | Size | Members |
| --- | --- | --- |
| `hkbBindable` | 48 | 0x10 `m_variableBindingSet` pointer; 0x18 `m_cachedBindables` and 0x28 `m_areBindablesCached` (ignored) |
| `hkbNode` | 72 | adds 0x30 `m_userData` (uint64), 0x38 `m_name` (`hkStringPtr`), 0x40 ignored members |
| `hkbGenerator` | 72 | adds nothing |
| `hkbModifier` | 80 | adds 0x48 `m_enable` (`hkBool`) and an ignored pad |

So a generator's own members start at 0x48, and a modifier's at 0x50. This is the most
useful rule on these pages.

Two inline structs repeat:

- `hkbEventProperty` (same as `hkbEventBase`), 16 bytes: int32 `m_id` at 0x00 and pointer
  `m_payload` at 0x08. `m_id` is a position in the graph's event list. -1 means no event.
- `hkVector4` and `hkQuaternion`, 16 bytes, four floats, 16-byte aligned.

## Walking a graph

A behavior graph is not a tree. Many nodes share one transition effect or one bone weight
list. So a walk from the root visits each object once. OpenSky also decodes every object
in the file, reachable or not, and counts decoded, skipped (no decoder), and failed objects
per class.

In every vanilla behavior file, the walk reaches exactly five objects fewer than the file
has. Those five sit above the node tree: the root container, the graph, its data, its
string data, and its variable value set. So the walk misses nothing.

## State machine classes

`hkbStateMachine`, size 264, comes from `hkbGenerator`. The root generator of every vanilla
player behavior file is a state machine.

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

`hkbStateMachineStateInfo`, size 120, comes from `hkbBindable`, **not** from `hkbNode`. So
its name is its own member at 0x60, not the inherited one at 0x38. This is the easiest
offset in this class set to get wrong.

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
wrap one `hkArray` at 0x10: of `hkbStateMachineTransitionInfo` (72 bytes each) and of
`hkbEventProperty` (16 bytes each).

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

`hkbClipGenerator`, size 272, is a leaf. It is the only class that names an animation.

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

`hkbClipTriggerArray`, size 32: `m_triggers` at 0x10, of `hkbClipTrigger` (32 bytes each):
`hkReal m_localTime` at 0x00, `hkbEventProperty m_event` at 0x08, then `hkBool`
`m_relativeToEndOfClip`, `m_acyclic`, and `m_isAnnotation` at 0x18, 0x19, and 0x1A. The
vanilla walk and run clips have empty triggers. Footsteps come from animation annotations
instead (see [hkaSplineCompressedAnimation](/formats/hka-animation.md#m_annotationtracks)).

`hkbBlenderGenerator`, size 160, runs several children at once and mixes their poses.

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

`hkbBlenderGeneratorChild`, size 80, comes from `hkbBindable`: `m_generator` at 0x30,
`m_boneWeights` at 0x38, `hkReal m_weight` at 0x40, `hkReal m_worldFromModelWeight` at
0x44.

`hkbPoseMatchingGenerator`, size 240, comes from `hkbBlenderGenerator`. Its own members
start at 0xA0: `hkQuaternion m_worldFromModelRotation` 0xA0,
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

`0_Master.hkb` uses `hkbBehaviorReferenceGenerator` to pull in the behavior files for each
activity. It names the file instead of pointing at it.
