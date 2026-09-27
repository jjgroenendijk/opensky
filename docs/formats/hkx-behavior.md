---
type: File Format
title: HKX Behavior Graph Objects
description: Graph-level Havok behavior classes in Skyrim SE packfiles - root container,
  behavior graph, graph data, string data, variable values, project and character data -
  and how OpenSky resolves pointers between objects.
tags: [format, havok, hkx, behavior, animation]
---

# HKX behavior graph objects

A behavior graph decides which animation an actor plays and how clips blend. It lives in
an HKX packfile (see [HKX container](/formats/hkx-container.md)). This page covers the
graph-level objects and how OpenSky follows pointers between objects. The node tree under
the graph's root is in [HKX behavior node classes](/formats/hkx-behavior-nodes.md). The
scope and clean-room rules are in
[Havok behavior scope](/decisions/havok-behavior-scope.md).

`openskycli hkx <key>` prints the objects of a file (see [CLI](/tools/cli.md)).

## References

There is no public Havok specification. Member offsets come from open projects and were
checked byte by byte against vanilla files:

- ret2end/HKX2Library (MIT): a Skyrim SE packfile reader and writer. Its member offset
  tables are the main source for this page. Its class signatures match the vanilla class
  name tables exactly (`hkRootLevelContainer` `0x2772C11E`, `hkbBehaviorGraph` `0xB1218F86`,
  `hkbBehaviorGraphData` `0x095ACA5D`, `hkbVariableValueSet` `0x27812D8D`,
  `hkbBehaviorGraphStringData` `0xC713064E`). This is why it can be trusted for this version.
- soulsmods/DSMapStudio HKX2 (MIT): a separate version of the same classes. Source for the
  order of `hkbVariableInfo::VariableType`.
- exyorha/hkxparse (MIT): packfile structures, for a cross-check.

No Havok SDK headers, no leaked or decompiled source, and no Bethesda code were used.

## Layout rules for every class

All vanilla behavior files are 64-bit little-endian `hk_2010.2.0-r1` packfiles.

| Construct | Size | Layout |
| --- | --- | --- |
| Pointer | 8 | Null on disk. Havok patches it at load from the fixup tables |
| `hkArray<T>` | 16 | Pointer at +0, int32 size at +8, uint32 capacity and flags at +12. Use size for the count. An empty array has a null pointer and no fixup |
| `hkStringPtr` | 8 | Pointer to a null-terminated ASCII string. Null means no string |
| `hkBaseObject` | 8 | vtable pointer |
| `hkReferencedObject` | 16 | `hkBaseObject`, uint16 size and flags at +8, int16 reference count at +10, padding. Derived classes start their members at 0x10 |

Members that Havok marks `SERIALIZE_IGNORED` still take their bytes in a packfile, as
zeros. So every offset on this page is the offset in memory, not a position in a packed
list.

## Following pointers

OpenSky indexes the section data, the fixups, and the class of every object in one file.
Following a pointer never crashes or throws. When it fails, OpenSky records the member and a
reason: no fixup, section missing, out of bounds, negative count, or string not decodable.
"No fixup" is normal: Havok writes a null pointer for an optional member that is not set.
Any other reason means the decoder read the wrong bytes. Local fixups are tried before
global ones, so a pointer into another section works the same way.

## hkRootLevelContainer

Every behavior, character, and project file has `hkRootLevelContainer` as its root. The role
of the file comes from the named variants in this object, not from the header or file name.
`hkRootLevelContainer` is 16 bytes: `m_namedVariants` at 0x00, an
`hkArray<hkRootLevelContainerNamedVariant>`.

`hkRootLevelContainerNamedVariant`, 24 bytes:

| Offset | Field | Type |
| --- | --- | --- |
| 0x00 | `m_name` | `hkStringPtr` |
| 0x08 | `m_className` | `hkStringPtr`, the class of the payload |
| 0x10 | `m_variant` | Pointer to the payload |

## hkbBehaviorGraph

The chain is `hkbGenerator -> hkbNode -> hkbBindable -> hkReferencedObject`. `hkbBindable`
ends at 0x30, and `hkbNode` takes 0x30 to 0x48. Size 304.

| Offset | Field | Type | Notes |
| --- | --- | --- | --- |
| 0x10 | `m_variableBindingSet` | pointer | From `hkbBindable` |
| 0x30 | `m_userData` | uint64 | From `hkbNode` |
| 0x38 | `m_name` | `hkStringPtr` | From `hkbNode`, for example `MT_Behavior.hkb` |
| 0x48 | `m_variableMode` | int8 | How variables survive reactivation |
| 0x80 | `m_rootGenerator` | pointer | Top of the node tree |
| 0x88 | `m_data` | pointer | `hkbBehaviorGraphData` |

## hkbBehaviorGraphData

Size 128. It declares the graph's variables and events. Nodes refer to them by position in
these lists.

| Offset | Field | Type |
| --- | --- | --- |
| 0x10 | `m_attributeDefaults` | `hkArray<hkReal>` |
| 0x20 | `m_variableInfos` | `hkArray<hkbVariableInfo>` |
| 0x30 | `m_characterPropertyInfos` | `hkArray<hkbVariableInfo>` |
| 0x40 | `m_eventInfos` | `hkArray<hkbEventInfo>` |
| 0x50 | `m_wordMinVariableValues` | `hkArray<hkbVariableValue>` |
| 0x60 | `m_wordMaxVariableValues` | `hkArray<hkbVariableValue>` |
| 0x70 | `m_variableInitialValues` | pointer to `hkbVariableValueSet` |
| 0x78 | `m_stringData` | pointer to `hkbBehaviorGraphStringData` |

Elements: `hkbVariableInfo` is 6 bytes (a 4-byte `hkbRoleAttribute`, int8 `m_type`, one
padding byte). `hkbEventInfo` is uint32 `m_flags`. `hkbVariableValue` is int32 `m_value`.

`VariableType`: -1 invalid, 0 bool, 1 int8, 2 int16, 3 int32, 4 real, 5 pointer, 6 vector3,
7 vector4, 8 quaternion. The vanilla names confirm this. In `mt_behavior.hkx`,
`bAnimationDriven` and `IsFirstPerson` are bool, `iSyncSprintState` and `iLeftHandType` are
int32, and `blendDefault`, `Direction`, and `SpeedSampled` are real.

## hkbBehaviorGraphStringData

Size 80. Four name lists, each an `hkArray<hkStringPtr>`, at 0x10 `m_eventNames`, 0x20
`m_attributeNames`, 0x30 `m_variableNames`, and 0x40 `m_characterPropertyNames`. Every
index in the graph is a position, so a null entry stays in its place.

## hkbVariableValueSet

Size 64. The starting value of every variable. The variable's type decides which list its
index points into: 0x10 `m_wordVariableValues` (`hkArray<hkbVariableValue>`, for bool, int,
and real), 0x20 `m_quadVariableValues` (`hkArray<hkVector4>`, 16 bytes each, for vectors and
quaternions), and 0x30 `m_variantVariableValues` (`hkArray<hkReferencedObject*>`, for
pointers). A real variable stores the bits of its float in the int32 word. Read the bits as
a float; do not convert the integer.

## hkbProjectData and hkbProjectStringData

A project file is the root of one behavior set. `hkbProjectData`, size 48: `m_worldUpWS`
(`hkVector4`) at 0x10, seen as (0, 0, 1, 0); `m_stringData` pointer at 0x20;
`m_defaultEventMode` (int8) at 0x28, seen as 2.

`hkbProjectStringData`, size 120: four `hkArray<hkStringPtr>` lists at 0x10
`m_animationFilenames`, 0x20 `m_behaviorFilenames`, 0x30 `m_characterFilenames`, and 0x40
`m_eventNames`. Then five `hkStringPtr`: 0x50 `m_animationPath`, 0x58 `m_behaviorPath`,
0x60 `m_characterPath`, 0x68 `m_fullPathToSource`, and 0x70 `m_rootPath`.

The three vanilla project files (`defaultmale.hkx`, `defaultfemale.hkx`,
`_1stperson\firstperson.hkx`) leave the three path members empty and name one character
file each. So paths are relative to the project file's folder.

## hkbCharacterData and hkbCharacterStringData

A character file links one behavior file to one rig and to its list of clips.
`hkbCharacterData`, size 176. OpenSky reads only `m_stringData`; the other rows let you
check the offset.

| Offset | Field | Type |
| --- | --- | --- |
| 0x60 | `m_characterPropertyInfos` | `hkArray<hkbVariableInfo>` |
| 0x80 | `m_characterPropertyValues` | pointer to `hkbVariableValueSet` |
| 0x98 | `m_stringData` | pointer to `hkbCharacterStringData` |
| 0xA8 | `m_scale` | `hkReal` |

`hkbCharacterStringData`, size 192. Offsets 0x10 to 0x90 are nine `hkArray<hkStringPtr>`
lists, in this order: `m_deformableSkinNames`, `m_rigidSkinNames`, `m_animationNames`,
`m_animationFilenames`, `m_characterPropertyNames`, `m_retargetingSkeletonMapperFilenames`,
`m_lodNames`, `m_mirroredSyncPointSubstringsA`, `m_mirroredSyncPointSubstringsB`. Then four
`hkStringPtr`: `m_name` 0xA0, `m_rigName` 0xA8, `m_ragdollName` 0xB0, `m_behaviorFilename`
0xB8.

The vanilla character files name `Behaviors\0_Master.hkx` as their behavior. The first
person files have a null `m_ragdollName`, because first person has no ragdoll.

## File role

The role comes from the class names of the root's variants, checked in this order:

| Variant class | Role |
| --- | --- |
| `hkbProjectData` | Project |
| `hkbCharacterData` | Character |
| `hkbBehaviorGraph` | Behavior |
| `hkaAnimationContainer` with a binding or spline animation | Animation |
| `hkaAnimationContainer` without one | Skeleton |
| anything else | Unknown |

The animation or skeleton split is a guess from the objects, not a field. It is wrong once
in vanilla: `animations\byoh\special_childdollplay2.hkx` has no binding or animation, so it
reads as a skeleton. It is really an animation file with no clips.

## Vanilla files

All 2,654 `.hkx` files under `meshes\actors\character\` (third and first person) are 64-bit
`hk_2010.2.0-r1` packfiles. There is no tagfile and no other Havok version. 35 are behavior
files (18 third person, 17 first person). Every behavior graph has a name, and every root
generator is an `hkbStateMachine`.

The behavior files use 55 object classes. 12 of them are Bethesda's own `BS*` classes, for
example `BSSynchronizedClipGenerator`, `BSIsActiveModifier`, `BSiStateTaggingGenerator`, and
`BSBoneSwitchGenerator`. So stock Havok classes alone do not cover the vanilla graphs. The
most common are `hkbStateMachineStateInfo`, `hkbClipGenerator`, `hkbClipTriggerArray`,
`hkbVariableBindingSet`, `hkbBlenderGeneratorChild`, and `hkbStateMachine`.

In all 2,654 files, the only pointer failures are the two first-person `m_ragdollName`
members, with reason "no fixup". No other reason appears anywhere. This is the evidence
that the offsets on this page are right.
