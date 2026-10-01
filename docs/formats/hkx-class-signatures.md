---
type: File Format
title: HKX Class Signatures
description: Class signatures of the Havok behavior classes in vanilla Skyrim SE files, used
  to confirm that a member offset table fits this Havok version.
tags: [format, havok, hkx, behavior]
---

# HKX class signatures

A packfile's class name table stores a 32-bit signature beside each class name. The
signature changes when a class's members change. So when a reference project lists the same
signature as a vanilla file, its member offsets fit that file.

Every signature below was read from the vanilla Skyrim SE behavior files
(hk_2010.2.0-r1, 64-bit little-endian). Each one matches ret2end/HKX2Library (MIT), the
main source for the member offsets in
[HKX behavior node classes](/formats/hkx-behavior-nodes.md) and
[HKX behavior modifier classes](/formats/hkx-behavior-modifiers.md). The graph-level
classes are listed in [HKX behavior graph objects](/formats/hkx-behavior.md).

## Stock Havok classes

| Class | Signature |
| --- | --- |
| `hkbNode` | `0x6D26F61D` |
| `hkbGenerator` | `0x0D68AEFC` |
| `hkbModifier` | `0x96EC5CED` |
| `hkbEventBase` | `0x76BDDB31` |
| `hkbStateMachine` | `0x816C1DCB` |
| `hkbStateMachineStateInfo` | `0x0ED7F9D0` |
| `hkbClipGenerator` | `0x333B85B9` |
| `hkbClipTriggerArray` | `0x59C23A0F` |
| `hkbClipTrigger` | `0x7EB45CEA` |
| `hkbBlenderGenerator` | `0x22DF7147` |
| `hkbBlenderGeneratorChild` | `0xE2B384B0` |
| `hkbPoseMatchingGenerator` | `0x29E271B4` |
| `hkbManualSelectorGenerator` | `0xD932FAB8` |
| `hkbModifierGenerator` | `0x1F81FAE6` |
| `hkbBehaviorReferenceGenerator` | `0x0FCB5423` |
| `hkbBlendingTransitionEffect` | `0xFD8584FE` |
| `hkbExpressionCondition` | `0x1C3C1045` |
| `hkbStringCondition` | `0x5AB50487` |
| `hkbExpressionDataArray` | `0x4B9EE1A2` |
| `hkbEventRangeDataArray` | `0x330A56EE` |
| `hkbVariableBindingSet` | `0x338AD4FF` |
| `hkbBoneWeightArray` | `0xCD902B77` |
| `hkbBoneIndexArray` | `0x00AA8619` |
| `hkbModifierList` | `0xA4180CA1` |
| `hkbEventDrivenModifier` | `0x7ED3F44E` |
| `hkbEvaluateExpressionModifier` | `0xF900F6BE` |
| `hkbEventsFromRangeModifier` | `0xBC561B6E` |
| `hkbTimerModifier` | `0x338B4879` |
| `hkbDampingModifier` | `0x9A040F03` |
| `hkbTwistModifier` | `0xB6B76B32` |
| `hkbRotateCharacterModifier` | `0x877EBC0B` |
| `hkbKeyframeBonesModifier` | `0x95F66629` |
| `hkbGetUpModifier` | `0x61CB7AC0` |
| `hkbFootIkControlsModifier` | `0xE5B6F544` |
| `hkbPoweredRagdollControlsModifier` | `0x7CB54065` |
| `hkbRigidBodyRagdollControlsModifier` | `0xAA87D1EB` |

## Bethesda classes

| Class | Signature |
| --- | --- |
| `BSSynchronizedClipGenerator` | `0xD83BEA64` |
| `BSiStateTaggingGenerator` | `0xF0826FC1` |
| `BSBoneSwitchGenerator` | `0xF33D3EEA` |
| `BSBoneSwitchGeneratorBoneData` | `0xC1215BE6` |
| `BSCyclicBlendTransitionGenerator` | `0x5119EB06` |
| `BSOffsetAnimationGenerator` | `0xB8571122` |
| `BSIsActiveModifier` | `0xB0FDE45A` |
| `BSEventEveryNEventsModifier` | `0x6030970C` |
| `BSEventOnDeactivateModifier` | `0x1062D993` |
| `BSEventOnFalseToTrueModifier` | `0x81D0777A` |
| `BSInterpValueModifier` | `0x29ADC802` |
| `BSModifyOnceModifier` | `0x1E20A97A` |
| `BSSpeedSamplerModifier` | `0xD297FDA9` |
| `BSRagdollContactListenerModifier` | `0x8003D8CE` |
| `BSDirectAtModifier` | `0x19A005C0` |
| `BSLookAtModifier` | `0xD756FC25` |
| `BSLookAtModifierBoneData` | `0x29EFEE59` |
