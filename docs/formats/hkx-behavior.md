---
type: File Format
title: HKX Behavior Graph Objects
description: Graph-level Havok behavior classes in Skyrim SE packfiles (root container,
  behavior graph, graph data, strings, variable values, project and character data) and what
  vanilla contains.
tags: [format, havok, hkx, behavior, animation]
---

# HKX behavior graph objects

A behavior graph decides which animation an actor plays. The
[HKX container](/formats/hkx-container.md) page shows how to find objects in a packfile. This
page covers the graph-level objects. The node tree under the root generator is on the
[behavior node classes](/formats/hkx-behavior-nodes.md) page.

`openskycli hkx <key>` prints a file's objects ([CLI](/tools/cli.md)).

## Sources

There is no public Havok specification. Member offsets come from open-source projects and were
checked byte by byte against the local SSE install.

- ret2end/HKX2Library (MIT): an SSE packfile reader and writer. Its offset tables and class
  signatures are the main source. Its signatures match the vanilla class-name tables exactly
  (`hkRootLevelContainer` `0x2772C11E`, `hkbBehaviorGraph` `0xB1218F86`, `hkbBehaviorGraphData`
  `0x095ACA5D`, `hkbVariableValueSet` `0x27812D8D`, `hkbBehaviorGraphStringData`
  `0xC713064E`). That is why it can be trusted for this Havok version.
- soulsmods/DSMapStudio HKX2 (MIT): a second reimplementation of the same classes. Source for
  the order of `hkbVariableInfo::VariableType`.
- exyorha/hkxparse (MIT): container structures, as a cross-check.

No Havok SDK, leaked source, or Bethesda code was used. See
[Havok behavior scope](/decisions/havok-behavior-scope.md).

## Shared layout rules

Every vanilla behavior file is a 64-bit little-endian `hk_2010.2.0-r1` packfile.

| Construct | Size | Layout |
| --- | --- | --- |
| pointer | 8 | Null on disk. The fixup tables give the real target |
| `hkArray<T>` | 16 | Pointer at +0, int32 size at +8, uint32 capacity and flags at +12. Use size. An empty array is a null pointer with no fixup |
| `hkStringPtr` | 8 | Pointer to a null-terminated ASCII string. Null is a valid absent string |
| `hkBaseObject` | 8 | Vtable pointer |
| `hkReferencedObject` | 16 | `hkBaseObject`, uint16 at +8, int16 at +10, padding. Subclasses start at 0x10 |

Members that Havok marks `SERIALIZE_IGNORED` still take their bytes in a packfile, written as
zeros. So every offset on this page is the full in-memory offset.

## Unresolved pointers

A pointer or array that cannot be resolved gives no value and a reason: `noFixup`,
`sectionMissing`, `outOfBounds`, `negativeCount`, or `undecodableString`. Only `noFixup` is
normal, because Havok writes a null pointer for an absent optional value. Any other reason
means the offset is wrong.

A pointer is looked up in the local fixups first, then in the global fixups. So a pointer
into another section works the same way.

## hkRootLevelContainer

The entry point of every behavior, character, and project file. The file's role comes from
the variants it holds, not from the header or the file name.

`hkRootLevelContainer` (16 bytes): `m_namedVariants` at 0x00, an
`hkArray<hkRootLevelContainerNamedVariant>`.

`hkRootLevelContainerNamedVariant` (24 bytes):

| Offset | Field | Type |
| --- | --- | --- |
| 0x00 | `m_name` | `hkStringPtr` |
| 0x08 | `m_className` | `hkStringPtr`, the Havok class of the payload |
| 0x10 | `m_variant` | Pointer to the payload |

## hkbBehaviorGraph (304 bytes)

The chain is `hkbGenerator -> hkbNode -> hkbBindable -> hkReferencedObject`. `hkbBindable`
ends at 0x30, and `hkbNode` uses 0x30 to 0x48.

| Offset | Field | Type | Notes |
| --- | --- | --- | --- |
| 0x10 | `m_variableBindingSet` | pointer | From `hkbBindable` |
| 0x30 | `m_userData` | uint64 | From `hkbNode` |
| 0x38 | `m_name` | `hkStringPtr` | From `hkbNode`. Example: `MT_Behavior.hkb` |
| 0x48 | `m_variableMode` | int8 enum | How variables survive reactivation |
| 0x80 | `m_rootGenerator` | pointer | Top of the node tree |
| 0x88 | `m_data` | pointer | To `hkbBehaviorGraphData` |

## hkbBehaviorGraphData (128 bytes)

The graph's declarations. Nodes refer to variables and events by index into these lists.

| Offset | Field | Type |
| --- | --- | --- |
| 0x10 | `m_attributeDefaults` | `hkArray<hkReal>` |
| 0x20 | `m_variableInfos` | `hkArray<hkbVariableInfo>` |
| 0x30 | `m_characterPropertyInfos` | `hkArray<hkbVariableInfo>` |
| 0x40 | `m_eventInfos` | `hkArray<hkbEventInfo>` |
| 0x50 | `m_wordMinVariableValues` | `hkArray<hkbVariableValue>` |
| 0x60 | `m_wordMaxVariableValues` | `hkArray<hkbVariableValue>` |
| 0x70 | `m_variableInitialValues` | Pointer to `hkbVariableValueSet` |
| 0x78 | `m_stringData` | Pointer to `hkbBehaviorGraphStringData` |

- `hkbVariableInfo` (6 bytes): a 4-byte role attribute, int8 `m_type` at 0x04, one padding
  byte.
- `hkbEventInfo` (4 bytes): uint32 flags.
- `hkbVariableValue` (4 bytes): int32 value.

`VariableType`: -1 invalid, 0 bool, 1 int8, 2 int16, 3 int32, 4 real, 5 pointer, 6 vector3,
7 vector4, 8 quaternion. Vanilla names confirm this: in `mt_behavior.hkx`, `bAnimationDriven`
and `IsFirstPerson` are bool, `iSyncSprintState` and `iLeftHandType` are int32, and
`blendDefault`, `Direction`, and `SpeedSampled` are real.

## hkbBehaviorGraphStringData (80 bytes)

Four name tables, each an `hkArray<hkStringPtr>`: `m_eventNames` (0x10), `m_attributeNames`
(0x20), `m_variableNames` (0x30), `m_characterPropertyNames` (0x40). A null entry stays in
place, because every index in the graph counts positions.

## hkbVariableValueSet (64 bytes)

The start value of every graph variable. The variable's type decides which list its index
uses.

| Offset | Field | Type |
| --- | --- | --- |
| 0x10 | `m_wordVariableValues` | `hkArray<hkbVariableValue>`: bool, int, real |
| 0x20 | `m_quadVariableValues` | `hkArray<hkVector4>`, 16 bytes each: vectors, quaternions |
| 0x30 | `m_variantVariableValues` | `hkArray<hkReferencedObject*>`: pointers |

A real variable stores its float bits in the word slot. Read it by reinterpreting the bits,
not by converting the integer.

## hkbProjectData (48 bytes) and hkbProjectStringData (120 bytes)

A project file is the root of one behavior set.

`hkbProjectData`: `m_worldUpWS` (`hkVector4` at 0x10, seen as `(0, 0, 1, 0)`), `m_stringData`
(pointer at 0x20), `m_defaultEventMode` (int8 at 0x28, seen as 2).

`hkbProjectStringData`: `hkArray<hkStringPtr>` fields `m_animationFilenames` (0x10),
`m_behaviorFilenames` (0x20), `m_characterFilenames` (0x30), `m_eventNames` (0x40); then
`hkStringPtr` fields `m_animationPath` (0x50), `m_behaviorPath` (0x58), `m_characterPath`
(0x60), `m_fullPathToSource` (0x68), `m_rootPath` (0x70).

## hkbCharacterData (176 bytes) and hkbCharacterStringData (192 bytes)

A character file ties one behavior file to one skeleton and to the clips the graph may play.

`hkbCharacterData`, the fields near the one OpenSky reads: `m_characterPropertyInfos`
(0x60), `m_characterPropertyValues` (0x80), `m_stringData` (pointer at 0x98), `m_scale`
(`hkReal` at 0xA8).

`hkbCharacterStringData`: `hkArray<hkStringPtr>` fields `m_deformableSkinNames` (0x10),
`m_rigidSkinNames` (0x20), `m_animationNames` (0x30), `m_animationFilenames` (0x40),
`m_characterPropertyNames` (0x50), `m_retargetingSkeletonMapperFilenames` (0x60),
`m_lodNames` (0x70), `m_mirroredSyncPointSubstringsA` (0x80),
`m_mirroredSyncPointSubstringsB` (0x90); then `hkStringPtr` fields `m_name` (0xA0),
`m_rigName` (0xA8), `m_ragdollName` (0xB0), `m_behaviorFilename` (0xB8).

## File role

The role comes from the variant classes in the root container, checked in this order:

| Variant class | Role |
| --- | --- |
| `hkbProjectData` | project |
| `hkbCharacterData` | character |
| `hkbBehaviorGraph` | behavior |
| `hkaAnimationContainer` with a binding or spline animation | animation |
| `hkaAnimationContainer` without one | skeleton |
| other | unknown |

The animation and skeleton split is a guess, and it is wrong once in vanilla:
`animations\byoh\special_childdollplay2.hkx` looks like a skeleton, because its container has
no clips. It is an animation file with an empty clip set.

## What vanilla contains

Under `meshes\actors\character\` (third person and `_1stperson`):

- Every file is a 64-bit `hk_2010.2.0-r1` packfile. There are no tagfiles and no other Havok
  versions, so OpenSky needs only this one container parser.
- The three project files (`defaultmale.hkx`, `defaultfemale.hkx`,
  `_1stperson\firstperson.hkx`) leave all three paths empty and name one character file each.
  So paths are relative to the project file's folder.
- The character files name `Behaviors\0_Master.hkx` as the behavior entry point.
- Every behavior graph's root generator is an `hkbStateMachine`.
- The graphs use 55 classes. 12 are Bethesda's own `BS*` classes, such as
  `BSSynchronizedClipGenerator` and `BSBoneSwitchGenerator`. So stock Havok classes alone
  are not enough.
- The only unresolved field is `m_ragdollName`, with reason `noFixup`, in the first-person
  character files. First person has no ragdoll, so that is correct. No other miss happens,
  which confirms the offsets on this page.
