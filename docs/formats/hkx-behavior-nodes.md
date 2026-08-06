---
type: File Format
title: HKX Behavior Node Classes
description: Byte layouts of every Havok Behavior node, modifier, condition and helper
  class the vanilla Skyrim SE player behavior files contain, the class registry that maps
  a class name to its decoder, and the graph walk built on it.
tags: [format, havok, hkx, behavior, animation, locomotion, milestone-14]
timestamp: 2026-08-03T00:00:00Z
---

# HKX behavior node classes

[HKX behavior graph objects](/formats/hkx-behavior.md) decodes the top of a behavior
packfile — the root container, `hkbBehaviorGraph`, and the variable and event
declarations — and stops at the graph's root generator. This page is the node tree below
that generator: every class the vanilla player behavior files actually contain, decoded.

The milestone rule ([Havok behavior scope](/decisions/havok-behavior-scope.md)) is
full-graph decode. Every class the census reports in those files has a decoder; a census
class without one is a failed sweep assertion, not a tolerated tally entry. Nothing here
evaluates anything — what a modifier does to a pose is a later item.

Parsers: `opensky/Engine/Formats/HKX/HKBClass.swift` (the shared protocol and the inherited
headers), `HKBBindables.swift`, `HKBStateMachine.swift`,
`HKBStateMachineTransitions.swift`, `HKBClipGenerator.swift`, `HKBBlenderGenerator.swift`,
`HKBSelectorGenerators.swift`, `HKBConditions.swift`, `HKBModifiers.swift`,
`HKBBoneModifiers.swift`, `HKBRagdollModifiers.swift`, `HKBBethesdaGenerators.swift`,
`HKBBethesdaModifiers.swift`, `HKBBethesdaAimModifiers.swift`. Registry and walk:
`HKBClassRegistry.swift`, `HKBGraphTopology.swift`. CLI dump: `openskycli hkx <key>`
([CLI](/tools/cli.md)). Tests: `HKBNodeClassTests` (three cases per class over synthetic
fixtures), `HKBGraphTopologyTests` (structural decode plus the walk), and the env-gated
`HKBNodeDecodeRealDataTests` sweep.

## Contents

- References
- Layout rules and the inherited headers
- The class registry
- Walking a graph
- State machine classes
- Generator classes
- Transition and condition classes
- Modifier classes
- Bethesda extension classes
- Known gaps
- Verification

## References

No public Havok specification. Member offsets are reimplemented from independent
open-source projects and then verified byte for byte against the local SSE install:

- ret2end/HKX2Library (MIT) — SSE-targeted packfile de/serialiser, and the only one of the
  three that carries Bethesda's `BS*` extension classes alongside the stock Havok ones. Its
  per-class member offset tables are the primary source for every layout below. The class
  signatures it records match the class-name table of the local vanilla files exactly,
  which is what makes it trustworthy for this file version; each decoder's file header
  quotes the signatures it relies on.
- soulsmods/DSMapStudio HKX2 (MIT) — independent reimplementation of the same stock class
  set, cross-checked.
- exyorha/hkxparse (MIT) — packfile container structures.

No Havok SDK headers, no decompiled or leaked source, and no Creation Kit or SKSE
internals were consulted (AGENTS.md "Legal & IP boundary").

## Layout rules and the inherited headers

The construct sizes (pointer 8, `hkArray` 16, `hkStringPtr` 8, `hkReferencedObject` 16) and
the rule that `SERIALIZE_IGNORED` members still occupy their bytes are the ones
[HKX behavior graph objects](/formats/hkx-behavior.md) records; every offset on this page
is an absolute in-memory offset in that profile.

Almost every class below derives from one of three bases, so those members repeat at fixed
offsets and OpenSky reads them once through `HKBNodeHeader` and `HKBModifierHeader`:

`hkbBindable`, size 48:

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x10 | `m_variableBindingSet` | pointer | the graph variables bound into this object |
| 0x18 | `m_cachedBindables` | `hkArray` | `SERIALIZE_IGNORED` |
| 0x28 | `m_areBindablesCached` | `hkBool` | `SERIALIZE_IGNORED` |

`hkbNode`, size 72, adds:

| off | field | type |
| --- | --- | --- |
| 0x30 | `m_userData` | `u64` |
| 0x38 | `m_name` | `hkStringPtr` |
| 0x40 | `m_id`, `m_cloneState`, `m_padNode` | `SERIALIZE_IGNORED` |

`hkbGenerator` (size 72) adds nothing of its own. `hkbModifier`, size 80, adds
`m_enable` (`hkBool`) at 0x48 and an ignored pad at 0x49. A generator's own members
therefore start at 0x48 and a modifier's at 0x50 — the single most useful rule on this
page.

Two more inline structs recur:

- `hkbEventProperty` (and its identical base `hkbEventBase`), 16 bytes: `i32 m_id` at 0x00,
  pointer `m_payload` at 0x08. `m_id` indexes the graph's event list; -1 means no event.
- `hkVector4` and `hkQuaternion`, 16 bytes, four floats, always 16-byte aligned.

## The class registry

`HKBClassRegistry` maps a Havok class name to a decoder. The class name comes from the
packfile's virtual-fixup inventory, so the name *is* the key; the class-name table's
signature hash identifies the same class and is recorded per decoder in the source
headers. Every decoder conforms to `HKBClass`, which exposes four things the generic
callers need:

| member | meaning |
| --- | --- |
| `className` | the Havok class name, as the packfile spells it |
| `nodeName` | `hkbNode::m_name`, or nil for the classes that carry no name |
| `references` | every object this one points at, each tagged with the member holding it |
| `unresolved` | the fields that did not resolve, with the reason |
| `summary` | one line of this class's own distinguishing field values |

There is deliberately no reflection and no class-layout table: each class declares its own
`HKXField(offset, "m_name")` constants and reads them through the shared cursor. The
registry is the only generic part, and it exists so a caller walks a graph without a switch
over class names.

## Walking a graph

Two views sit on the registry:

- `HKBGraphTopology.walk(from:in:)` follows `references` down from a root generator,
  first-visit-wins. A behavior graph is a DAG rather than a tree — a transition effect or a
  bone weight array is shared by many nodes — so a repeat reference is not re-decoded.
  Records the classes it reached but could not decode, and the references that landed on a
  location registering no class at all.
- `HKBDecodeReport.decodeAll(in:)` decodes every registered object in a file regardless of
  reachability, and reports decoded, skipped (no decoder) and failed (decoder returned nil)
  counts per class. This is what the real-data sweep asserts against.

## State machine classes

`hkbStateMachine`, size 264, derives `hkbGenerator`. Every vanilla player behavior file's
root generator is one of these.

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

`hkbStateMachineStateInfo`, size 120, derives `hkbBindable` — **not** `hkbNode**, so its
name is its own member at 0x60 rather than the inherited one at 0x38. That is the easiest
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

`hkbClipGenerator`, size 272 — the leaf, and the only class that names an animation.

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

`hkbBlenderGenerator`, size 160 — runs several children at once and mixes their poses.

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

`hkbBehaviorReferenceGenerator` is how `0_Master.hkb` pulls in the per-activity behavior
files: it names the file rather than pointing at it, so resolving the name to a loaded
graph is a later item's job.

## Transition and condition classes

`hkbTransitionEffect`, size 80, derives `hkbGenerator` and adds `i8 m_selfTransitionMode`
at 0x48 and `i8 m_eventMode` at 0x49. `hkbBlendingTransitionEffect`, size 144, derives it:

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x50 | `m_duration` | `hkReal` | blend length in seconds |
| 0x54 | `m_toGeneratorStartTimeFraction` | `hkReal` | |
| 0x58 | `m_flags` | `u16` bit set | 1 ignore from-generator, 2 sync, 4 ignore world-from-model |
| 0x5A | `m_endMode` | `i8` enum | |
| 0x5B | `m_blendCurve` | `i8` enum | 0 smooth, 1 linear, 2 linear-to-ease, 3 ease-to-linear |

Conditions carry their test as authored text; the compiled form Havok rebuilds at load is
`SERIALIZE_IGNORED`.

| class | size | members |
| --- | --- | --- |
| `hkbExpressionCondition` | 32 | `m_expression` `hkStringPtr` 0x10 |
| `hkbStringCondition` | 24 | `m_conditionString` `hkStringPtr` 0x10 |
| `hkbStringEventPayload` | 24 | `m_data` `hkStringPtr` 0x10 |
| `hkbExpressionDataArray` | 32 | `m_expressionsData` 0x10, `hkbExpressionData` stride 24 |
| `hkbEventRangeDataArray` | 32 | `m_eventData` 0x10, `hkbEventRangeData` stride 32 |

`hkbExpressionData`, 24 bytes: `m_expression` `hkStringPtr` 0x00, `i32
m_assignmentVariableIndex` 0x08, `i32 m_assignmentEventIndex` 0x0C, `i8 m_eventMode` 0x10.

`hkbEventRangeData`, 32 bytes: `hkReal m_upperBound` 0x00, `hkbEventProperty m_event` 0x08,
`i8 m_eventMode` 0x18.

## Modifier classes

`hkbVariableBindingSet`, size 40, is the mechanism the whole graph is driven through:
`m_bindings` at 0x10 (`hkbVariableBindingSetBinding`, stride 40) and
`i32 m_indexOfBindingToEnable` at 0x20. One binding maps a member path on the owning object
to a graph variable index:

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x00 | `m_memberPath` | `hkStringPtr` | e.g. `m_blendParameter`; empty binds the object |
| 0x1C | `m_variableIndex` | `i32` | |
| 0x20 | `m_bitIndex` | `i8` | -1 when not bit-addressed |
| 0x21 | `m_bindingType` | `i8` enum | 0 graph variable, 1 character property |

The two bone-list classes derive `hkbBindable`, both size 64, both with their array at
0x30: `hkbBoneWeightArray::m_boneWeights` (`hkArray<hkReal>`) and
`hkbBoneIndexArray::m_boneIndices` (`hkArray<hkInt16>`).

Stock modifiers, all deriving `hkbModifier` so their own members start at 0x50:

| class | size | members |
| --- | --- | --- |
| `hkbModifierList` | 96 | `m_modifiers` `hkArray<hkbModifier*>` 0x50 |
| `hkbEventDrivenModifier` | 104 | `m_modifier` 0x50 (from `hkbModifierWrapper`), `i32 m_activateEventId` 0x58, `i32 m_deactivateEventId` 0x5C, `hkBool m_activeByDefault` 0x60 |
| `hkbEvaluateExpressionModifier` | 112 | `m_expressions` 0x50 |
| `hkbEventsFromRangeModifier` | 112 | `hkReal m_inputValue` 0x50, `hkReal m_lowerBound` 0x54, `m_eventRanges` 0x58 |
| `hkbTimerModifier` | 112 | `hkReal m_alarmTimeSeconds` 0x50, `hkbEventProperty m_alarmEvent` 0x58 |
| `hkbDampingModifier` | 192 | `m_kP` 0x50, `m_kI` 0x54, `m_kD` 0x58, `hkBool m_enableScalarDamping` 0x5C, `m_enableVectorDamping` 0x5D, `m_rawValue` 0x60, `m_dampedValue` 0x64, vectors at 0x70, 0x80, 0x90, 0xA0, `m_errorSum` 0xB0, `m_previousError` 0xB4 |
| `hkbTwistModifier` | 144 | `hkVector4 m_axisOfRotation` 0x50, `hkReal m_twistAngle` 0x60, `i16 m_startBoneIndex` 0x64, `i16 m_endBoneIndex` 0x66, `i8 m_setAngleMethod` 0x68, `i8 m_rotationAxisCoordinates` 0x69, `hkBool m_isAdditive` 0x6A |
| `hkbRotateCharacterModifier` | 128 | `hkReal m_degreesPerSecond` 0x50, `hkReal m_speedMultiplier` 0x54, `hkVector4 m_axisOfRotation` 0x60 |
| `hkbKeyframeBonesModifier` | 104 | `m_keyframeInfo` 0x50 (stride 48), `m_keyframedBonesList` 0x60 |
| `hkbGetUpModifier` | 128 | `hkVector4 m_groundNormal` 0x50, `hkReal m_duration` 0x60, `hkReal m_alignWithGroundDuration` 0x64, `i16` bone indices 0x68, 0x6A, 0x6C |
| `hkbFootIkControlsModifier` | 176 | `m_controlData.m_gains` (12 `hkReal`) 0x50, `m_legs` 0x80 (stride 48), `hkVector4 m_errorOutTranslation` 0x90, `hkQuaternion m_alignWithGroundRotation` 0xA0 |
| `hkbPoweredRagdollControlsModifier` | 144 | control data floats 0x50-0x60, `m_bones` 0x70, world-from-model mode data 0x78-0x7E, `m_boneWeights` 0x80 |
| `hkbRigidBodyRagdollControlsModifier` | 160 | `m_controlData.m_durationToBlend` 0x80, `m_bones` 0x90 |

`hkbKeyframeBonesModifierKeyframeInfo`, 48 bytes: `hkVector4 m_keyframedPosition` 0x00,
`hkQuaternion m_keyframedRotation` 0x10, `i16 m_boneIndex` 0x20, `hkBool m_isValid` 0x22.

`hkbFootIkControlsModifierLeg`, 48 bytes: `hkVector4 m_groundPosition` 0x00,
`hkbEventProperty m_ungroundedEvent` 0x10, `hkReal m_verticalError` 0x20,
`hkBool m_hitSomething` 0x24, `hkBool m_isPlantedMS` 0x25.

## Bethesda extension classes

Twelve of the 55 classes in the vanilla player behavior files are Bethesda's own. They
register in the packfile exactly like stock classes and derive from the stock bases.

| class | size | members |
| --- | --- | --- |
| `BSSynchronizedClipGenerator` | 304 | `m_pClipGenerator` 0x50, `m_SyncAnimPrefix` `hkStringPtr` 0x58, `hkBool m_bSyncClipIgnoreMarkPlacement` 0x60, `hkReal m_fGetToMarkTime` 0x64, `hkReal m_fMarkErrorThreshold` 0x68, `hkBool m_bLeadCharacter` 0x6C, `m_bReorientSupportChar` 0x6D, `m_bApplyMotionFromRoot` 0x6E, `i16 m_sAnimationBindingIndex` 0x128 |
| `BSiStateTaggingGenerator` | 96 | `m_pDefaultGenerator` 0x50, `i32 m_iStateToSetAs` 0x58, `i32 m_iPriority` 0x5C |
| `BSBoneSwitchGenerator` | 112 | `m_pDefaultGenerator` 0x50, `m_ChildrenA` 0x58 |
| `BSBoneSwitchGeneratorBoneData` | 64 | `m_pGenerator` 0x30, `m_spBoneWeight` 0x38 |
| `BSCyclicBlendTransitionGenerator` | 176 | `m_pBlenderGenerator` 0x50, `m_EventToFreezeBlendValue` 0x58, `m_EventToCrossBlend` 0x68, `hkReal m_fBlendParameter` 0x78, `hkReal m_fTransitionDuration` 0x7C, `i8 m_eBlendCurve` 0x80 |
| `BSOffsetAnimationGenerator` | 176 | `m_pDefaultGenerator` 0x50, `m_pOffsetClipGenerator` 0x60, `hkReal m_fOffsetVariable` 0x68, `m_fOffsetRangeStart` 0x6C, `m_fOffsetRangeEnd` 0x70 |
| `BSIsActiveModifier` | 96 | five `(m_bIsActiveN, m_bInvertActiveN)` `hkBool` pairs from 0x50, pitch 2 |
| `BSEventEveryNEventsModifier` | 128 | `m_eventToCheckFor` 0x50, `m_eventToSend` 0x60, `i8 m_numberOfEventsBeforeSend` 0x70, `i8 m_minimumNumberOfEventsBeforeSend` 0x71, `hkBool m_randomizeNumberOfEvents` 0x72 |
| `BSEventOnDeactivateModifier` | 96 | `m_event` 0x50 |
| `BSEventOnFalseToTrueModifier` | 160 | three slots from 0x50, pitch 0x18: `hkBool m_bEnableEventN` +0x00, `hkBool m_bVariableToTestN` +0x01, `hkbEventProperty m_EventToSendN` +0x08 |
| `BSInterpValueModifier` | 104 | `m_source` 0x50, `m_target` 0x54, `m_result` 0x58, `m_gain` 0x5C |
| `BSModifyOnceModifier` | 112 | `m_pOnActivateModifier` 0x50, `m_pOnDeactivateModifier` 0x60 |
| `BSSpeedSamplerModifier` | 96 | `i32 m_state` 0x50, `hkReal m_direction` 0x54, `hkReal m_goalSpeed` 0x58, `hkReal m_speedOut` 0x5C |
| `BSRagdollContactListenerModifier` | 136 | `m_contactEvent` 0x58, `m_bones` 0x68 |
| `BSDirectAtModifier` | 224 | `hkBool m_directAtTarget` 0x50, `i16` bone indices 0x52, 0x54, 0x56, four `hkReal` limits and offsets 0x58-0x64, `m_onGain` 0x68, `m_offGain` 0x6C, `hkVector4 m_targetLocation` 0x70, `u32 m_userInfo` 0x80, `hkBool m_directAtCamera` 0x84, camera X/Y/Z 0x88/0x8C/0x90, `hkBool m_active` 0x94, `m_currentHeadingOffset` 0x98, `m_currentPitchOffset` 0x9C |
| `BSLookAtModifier` | 224 | `hkBool m_lookAtTarget` 0x50, `m_bones` 0x58, `m_eyeBones` 0x68 (both stride 64), `m_limitAngleDegrees` 0x78, `m_limitAngleThresholdDegrees` 0x7C, `hkBool m_continueLookOutsideOfLimit` 0x80, `m_onGain` 0x84, `m_offGain` 0x88, `hkBool m_useBoneGains` 0x8C, `hkVector4 m_targetLocation` 0x90, `hkBool m_targetOutsideLimits` 0xA0, `m_targetOutOfLimitEvent` 0xA8, `hkBool m_lookAtCamera` 0xB8, camera X/Y/Z 0xBC/0xC0/0xC4 |

`BSLookAtModifierBoneData`, 64 bytes: `i16 m_index` 0x00, `hkVector4 m_fwdAxisLS` 0x10,
`hkReal m_limitAngleDegrees` 0x20, `m_onGain` 0x24, `m_offGain` 0x28, `hkBool m_enabled`
0x2C.

`BSSynchronizedClipGenerator` and `BSBoneSwitchGenerator` are the two that matter most for
the player: the first drives paired animations (killmoves, furniture), the second is how
the first-person arms run a different clip from the body.

## Known gaps

- `hkbRigidBodyRagdollControlsModifier::m_controlData` embeds a 48-byte
  `hkaKeyFrameHierarchyUtilityControlData`, an hka physics class rather than an hkb
  behavior one. Its members are not confirmed against the local files, so OpenSky decodes
  `m_durationToBlend` past the block and the bone list, and leaves the block itself
  undecoded. It is physics tuning, which the milestone scope puts in a later milestone.
- `hkbFootIkControlData::m_gains` is decoded as twelve floats in Havok's declared order
  rather than as twelve named members. Nothing in this milestone reads an individual gain,
  and naming them now would be twelve chances to be wrong about a class the physics work
  will re-derive anyway.
- `hkbStateMachineStateInfo::m_listeners` (`hkArray<hkbStateListener*>` at 0x30) is empty in
  every vanilla file, so its element type is recorded but not decoded.
- The `SERIALIZE_IGNORED` runtime members — current state ids, elapsed times, cached
  bindables — are deliberately not decoded. They occupy their bytes and a packfile writes
  them as zeros, so reading them would report the file's zeros rather than any state.

## Verification

Sweep of every behavior-role `.hkx` under `meshes\actors\character\` in the local SSE
install (third-person plus `_1stperson`), 2026-08-03, produced by
`HKBNodeDecodeRealDataTests` and captured to the gitignored `logs/hkx-behavior-nodes.log`.
Reproduce with
`make realtest T='HKBNodeDecodeRealDataTests/decodesEveryBehaviorNodeClass()'`, or inspect
one file with `openskycli hkx <key>`.

35 behavior files, 31,719 objects decoded, zero objects with no decoder, zero decode
failures. All 55 classes the census reports are covered: the 50 node classes on this page
plus the five graph-level classes item 14.1 decodes. Every file's root generator is an
`hkbStateMachine`, and every file's walk reaches exactly five fewer nodes than the file has
objects — the root container, the behavior graph, its data, its string data, and its
variable value set are the five that hang above the node tree rather than inside it, which
is the arithmetic that shows the walk misses nothing.

Unresolved fields across the set: 58,076 `noFixup` and nothing else. Not one `outOfBounds`,
`sectionMissing`, `negativeCount`, or `undecodableString` occurs anywhere, which is the
evidence that every offset on this page is right.

The sweep asserts the full-graph rule directly: for each of the 35 behavior files, every
class the file declares has a registered decoder (`uncoveredClassNames` empty), every
object of every such class decodes (`failedCounts` empty), the walk from the root generator
reaches at least one node, and no member reports a miss other than `noFixup`. A `noFixup`
miss is the ordinary absent optional — most nodes carry no variable binding set — while any
`outOfBounds`, `sectionMissing`, `negativeCount`, or `undecodableString` would mean a
decoder read the wrong bytes, which is the evidence every offset on this page rests on.

Fixing the truncated-object test case surfaced one real gap in the shared helper from item
14.1: `HKXObjectCursor.pointer(at:)` did not bounds-check the member's own eight bytes, so a
pointer running off the end of a short object reported `noFixup` — indistinguishable from a
null optional — instead of `outOfBounds`. It now checks first. That distinction is what the
sweep assertion above rests on, so the helper was wrong in exactly the way the assertion
was designed to catch.

Synthetic coverage, `HKBNodeClassTests`, runs three cases against every class in the
registry: a zero-filled object of the class's declared Havok size decodes with no miss
other than `noFixup` (so no decoder reads past its own class), a 16-byte-truncated object
still decodes and reports out-of-bounds members rather than trapping, and a pointer patched
to a section the file does not define reports `sectionMissing`. The size column in that
test's table is the same size column as this page, so a layout that disagreed with a
decoder's highest offset fails there.
