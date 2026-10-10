---
type: File Format
title: HKX Behavior Modifier Classes
description: Byte layouts of Havok behavior transitions, conditions, bindings, modifiers,
  and Bethesda's own BS* classes in vanilla Skyrim SE player behavior files.
tags: [format, havok, hkx, behavior, animation]
---

# HKX behavior modifier classes

This page continues [HKX behavior node classes](/formats/hkx-behavior-nodes.md). It covers
transitions and conditions, variable bindings, the modifier classes, and Bethesda's own
`BS*` classes. The shared headers and sources are on that page. A modifier's own members
start at 0x50.

## Transition and condition classes

`hkbTransitionEffect`, size 80, comes from `hkbGenerator` and adds `i8 m_selfTransitionMode`
at 0x48 and `i8 m_eventMode` at 0x49. `hkbBlendingTransitionEffect`, size 144, comes from it:

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x50 | `m_duration` | `hkReal` | blend length in seconds |
| 0x54 | `m_toGeneratorStartTimeFraction` | `hkReal` | |
| 0x58 | `m_flags` | `u16` bit set | 1 ignore from-generator, 2 sync, 4 ignore world-from-model |
| 0x5A | `m_endMode` | `i8` enum | |
| 0x5B | `m_blendCurve` | `i8` enum | 0 smooth, 1 linear, 2 linear-to-ease, 3 ease-to-linear |

A condition stores its test as text. Havok compiles it at load, and the compiled form is
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

`hkbVariableBindingSet`, size 40, is how graph variables drive the whole graph:
`m_bindings` at 0x10 (`hkbVariableBindingSetBinding`, 40 bytes each) and
`i32 m_indexOfBindingToEnable` at 0x20. One binding links a member of the owning object to
a graph variable:

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x00 | `m_memberPath` | `hkStringPtr` | e.g. `m_blendParameter`; empty binds the object |
| 0x1C | `m_variableIndex` | `i32` | |
| 0x20 | `m_bitIndex` | `i8` | -1 when not bit-addressed |
| 0x21 | `m_bindingType` | `i8` enum | 0 graph variable, 1 character property |

The two bone list classes come from `hkbBindable`. Both are size 64 with their array at
0x30: `hkbBoneWeightArray::m_boneWeights` (`hkArray<hkReal>`) and
`hkbBoneIndexArray::m_boneIndices` (`hkArray<hkInt16>`).

Stock modifiers. All come from `hkbModifier`, so their own members start at 0x50:

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

12 of the 55 classes in the vanilla player behavior files are Bethesda's own. They are
stored like stock classes and come from the stock bases.

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

Two matter most for the player. `BSSynchronizedClipGenerator` drives paired animations
(kill moves, furniture). `BSBoneSwitchGenerator` lets the first-person arms play a different
clip from the body.

## Not decoded

- `hkbRigidBodyRagdollControlsModifier`: OpenSky reads `m_durationToBlend` as the blend
  time from animation to physics (see [ragdoll](/engine/ragdoll.md)). It does not read
  `m_bones`: the ragdoll uses every bone that has a body in the skeleton NIF.
  `hkbPoweredRagdollControlsModifier` gives the motor settings, and
  `BSRagdollContactListenerModifier` gives the contact event. Neither reads its `m_bones`.
- `hkbRigidBodyRagdollControlsModifier::m_controlData` holds a 48-byte
  `hkaKeyFrameHierarchyUtilityControlData`. This is a physics class, and its members are not
  confirmed against vanilla files. OpenSky skips it.
- `hkbFootIkControlData::m_gains` is read as twelve floats in Havok's order, not as named
  members. Nothing reads a single gain, and twelve guessed names could be wrong.
- `hkbStateMachineStateInfo::m_listeners` is empty in every vanilla file, so its elements
  are not decoded.
- `SERIALIZE_IGNORED` members (current state, elapsed time, cached values) are zeros on disk
  and are not read.

## Vanilla files

All 35 vanilla behavior files decode: about 32,000 objects, none without a decoder, and no
failures. The only pointer misses are "no fixup" (an optional pointer that is not set). No
other reason appears. This is the evidence that the offsets on these pages are right.
