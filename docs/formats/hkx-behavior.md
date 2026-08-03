---
type: File Format
title: HKX Behavior Graph Objects
description: Graph-level Havok behavior classes in Skyrim SE packfiles — root container,
  hkbBehaviorGraph, graph data, string data, variable value set, project and character
  string data — plus the shared object-graph resolution helpers and the vanilla census.
tags: [format, havok, hkx, behavior, animation, milestone-14]
timestamp: 2026-08-03T00:00:00Z
---

# HKX behavior graph objects

The [HKX packfile container](/formats/hkx-container.md) locates objects; this page covers
the graph-level objects a Havok *behavior* packfile carries, and the shared helpers every
object decoder now resolves its pointers through. Node and modifier classes — the tree the
graph's root generator heads — are a separate item and are not documented here yet.

Parsers: `opensky/Formats/HKX/HKXObjectGraph.swift`, `HKXObjectCursor.swift`,
`HKXObjectCursorArrays.swift` (shared resolution); `HKBRootLevelContainer.swift`,
`HKBBehaviorGraph.swift`, `HKBBehaviorStrings.swift`, `HKBFileStringData.swift` (classes);
`HKBBehaviorCensus.swift` (the summary). CLI dump: `openskycli hkx <key>`
([CLI](/tools/cli.md)). Tests: `HKXObjectGraphTests` and `HKBBehaviorGraphTests` over
synthetic fixtures, plus the env-gated `HKBBehaviorCensusRealDataTests` sweep.

## Contents

- References
- Layout rules shared by every class
- Shared resolution helpers
- `hkRootLevelContainer` and named variants
- `hkbBehaviorGraph`
- `hkbBehaviorGraphData`
- `hkbBehaviorGraphStringData`
- `hkbVariableValueSet`
- `hkbProjectData` and `hkbProjectStringData`
- `hkbCharacterData` and `hkbCharacterStringData`
- File role
- Verification

## References

No public Havok specification. Member offsets are reimplemented from independent
open-source projects and then verified byte for byte against the local SSE install:

- ret2end/HKX2Library (MIT) — SSE-targeted packfile de/serialiser. Its per-class member
  offset tables and its class signatures are the primary source for every layout below.
  The signatures it records match the class-name table of the local vanilla files exactly
  (`hkRootLevelContainer` 0x2772C11E, `hkbBehaviorGraph` 0xB1218F86, `hkbBehaviorGraphData`
  0x095ACA5D, `hkbVariableValueSet` 0x27812D8D, `hkbBehaviorGraphStringData` 0xC713064E),
  which is what makes it trustworthy for this file version.
- soulsmods/DSMapStudio HKX2 (MIT) — independent reimplementation of the same class set;
  source for the `hkbVariableInfo::VariableType` ordering.
- exyorha/hkxparse (MIT) — packfile container structures, cross-checked.

No Havok SDK headers, no decompiled or leaked source, and no Bethesda code were consulted
(AGENTS.md "Legal & IP boundary"). The scope and the clean-room rule are recorded in
[Havok behavior scope](/decisions/havok-behavior-scope.md).

## Layout rules shared by every class

All vanilla SSE behavior files are 64-bit little-endian `hk_2010.2.0-r1` packfiles, the
same profile the container page records; the sweep asserts this rather than assuming it.
Within that profile:

| Construct | Size | Layout |
| --- | --- | --- |
| pointer | 8 | Null on disk. The Havok "finish" pass patches it at load, so the fixup tables *are* the pointer values. |
| `hkArray<T>` | 16 | `ptr` at +0, `i32 size` at +8, `u32 capacityAndFlags` at +12. Bit 31 of capacity is a Havok flag, so `size` drives element counts. An empty array is a null pointer with no fixup. |
| `hkStringPtr` | 8 | Pointer to an in-place NUL-terminated ASCII string. Null is a legitimate absent string. |
| `hkBaseObject` | 8 | Vtable pointer. |
| `hkReferencedObject` | 16 | `hkBaseObject`, then `u16 memSizeAndFlags` at +8 and `i16 referenceCount` at +10, padded to 8. Every class below that derives from it starts its own members at 0x10. |

Members Havok flags `SERIALIZE_IGNORED` still occupy their bytes in a packfile — they are
written as zeros, not omitted. Every offset in this page is therefore the absolute
in-memory offset, not a position in a packed sequence.

## Shared resolution helpers

`HKXObjectGraph` indexes one parsed `HKXFile`: section payloads, local and global fixups
keyed by source offset, and the class name of every registered object keyed by its
location. `HKXObjectCursor` is a read position on one object (or one array element); a
class decoder declares its members as `HKXField(offset, "m_name")` constants and reads
them through the cursor.

Resolution never traps and never throws. An unresolvable field yields nil and appends an
`HKXUnresolvedReference` naming the member and one of five reasons — `noFixup`,
`sectionMissing`, `outOfBounds`, `negativeCount`, `undecodableString`. A caller that
treats a field as load-bearing converts the nil into its own typed error;
`hkaSkeleton`, `hkaSplineCompressedAnimation`, and `hkaAnimationBinding` all do exactly
that and keep the error enums they already had.

`noFixup` is the one miss that is not a bug: Havok writes a null pointer for an absent
optional. Every other reason means the decoder read the wrong bytes, which is what the
real-data sweep asserts against.

Pointer resolution tries the local fixups first, then the global ones, so a pointer into
another section resolves the same way as an intra-section one; an array's elements are
read from whichever section the array's own fixup lands in.

## `hkRootLevelContainer` and named variants

The entry point. Every behavior, character, and project file declares
`hkRootLevelContainer` as the container header's root class, so the *file's* role comes
from the named variants this object carries, not from the header and not from the
filename.

`hkRootLevelContainer`, 16 bytes, no base class:

| off | field | type |
| --- | --- | --- |
| 0x00 | `m_namedVariants` | `hkArray<hkRootLevelContainerNamedVariant>` |

`hkRootLevelContainerNamedVariant`, 24 bytes, the array's element stride:

| off | field | type |
| --- | --- | --- |
| 0x00 | `m_name` | `hkStringPtr` — authored name |
| 0x08 | `m_className` | `hkStringPtr` — Havok class name of the payload |
| 0x10 | `m_variant` | pointer to the payload object |

## `hkbBehaviorGraph`

Derives `hkbGenerator` -> `hkbNode` -> `hkbBindable` -> `hkReferencedObject`, so the
inherited members land first: `hkbBindable` ends at 0x30, `hkbNode` occupies 0x30-0x48,
and the graph's own members follow. Total size 304.

| off | field | type | notes |
| --- | --- | --- | --- |
| 0x10 | `m_variableBindingSet` | pointer | from `hkbBindable` |
| 0x30 | `m_userData` | `u64` | from `hkbNode` |
| 0x38 | `m_name` | `hkStringPtr` | from `hkbNode`; the graph name, e.g. `MT_Behavior.hkb` |
| 0x48 | `m_variableMode` | `i8` enum | how variables survive re-activation |
| 0x80 | `m_rootGenerator` | pointer to `hkbGenerator` | head of the node tree |
| 0x88 | `m_data` | pointer to `hkbBehaviorGraphData` | |

OpenSky decodes the name, user data, variable mode, and both pointers, and resolves the
root generator's *class* through the object inventory. It does not walk the node tree.

## `hkbBehaviorGraphData`

Derives `hkReferencedObject`; size 128. Holds the graph's declarations. Variable and
event indices used by nodes address these lists positionally.

| off | field | type |
| --- | --- | --- |
| 0x10 | `m_attributeDefaults` | `hkArray<hkReal>` |
| 0x20 | `m_variableInfos` | `hkArray<hkbVariableInfo>` |
| 0x30 | `m_characterPropertyInfos` | `hkArray<hkbVariableInfo>` |
| 0x40 | `m_eventInfos` | `hkArray<hkbEventInfo>` |
| 0x50 | `m_wordMinVariableValues` | `hkArray<hkbVariableValue>` |
| 0x60 | `m_wordMaxVariableValues` | `hkArray<hkbVariableValue>` |
| 0x70 | `m_variableInitialValues` | pointer to `hkbVariableValueSet` |
| 0x78 | `m_stringData` | pointer to `hkbBehaviorGraphStringData` |

Element structs:

- `hkbVariableInfo`, 6 bytes: a 4-byte `hkbRoleAttribute` at 0x00, then `i8 m_type` at
  0x04 and one padding byte.
- `hkbEventInfo`, 4 bytes: `u32 m_flags`.
- `hkbVariableValue`, 4 bytes: `i32 m_value`. An array of them reads exactly like an
  `hkArray<hkInt32>`.

`hkbVariableInfo::VariableType`: -1 invalid, 0 bool, 1 int8, 2 int16, 3 int32, 4 real,
5 pointer, 6 vector3, 7 vector4, 8 quaternion.

## `hkbBehaviorGraphStringData`

Derives `hkReferencedObject`; size 80. Four parallel name tables, all
`hkArray<hkStringPtr>`. OpenSky keeps them index-preserving — a null entry is nil in
place, never dropped — because every index in the graph is positional.

| off | field |
| --- | --- |
| 0x10 | `m_eventNames` |
| 0x20 | `m_attributeNames` |
| 0x30 | `m_variableNames` |
| 0x40 | `m_characterPropertyNames` |

## `hkbVariableValueSet`

Derives `hkReferencedObject`; size 64. The initial value of every graph variable. A
variable's declared type decides which list its index addresses.

| off | field | type |
| --- | --- | --- |
| 0x10 | `m_wordVariableValues` | `hkArray<hkbVariableValue>` — bool, int, and real |
| 0x20 | `m_quadVariableValues` | `hkArray<hkVector4>`, stride 16 — vector and quaternion |
| 0x30 | `m_variantVariableValues` | `hkArray<hkReferencedObject*>` — pointer variables |

A real-typed variable stores its float as the bit pattern of its word slot, which is why
`HKBVariableValueSet.realValue(at:)` reinterprets rather than converts.

## `hkbProjectData` and `hkbProjectStringData`

A project file is the root of one behavior set. `hkbProjectData` derives
`hkReferencedObject`; size 48.

| off | field | type |
| --- | --- | --- |
| 0x10 | `m_worldUpWS` | `hkVector4` (observed `(0, 0, 1, 0)`) |
| 0x20 | `m_stringData` | pointer to `hkbProjectStringData` |
| 0x28 | `m_defaultEventMode` | `i8` enum (observed 2) |

`hkbProjectStringData` derives `hkReferencedObject`; size 120.

| off | field | type |
| --- | --- | --- |
| 0x10 | `m_animationFilenames` | `hkArray<hkStringPtr>` |
| 0x20 | `m_behaviorFilenames` | `hkArray<hkStringPtr>` |
| 0x30 | `m_characterFilenames` | `hkArray<hkStringPtr>` |
| 0x40 | `m_eventNames` | `hkArray<hkStringPtr>` |
| 0x50 | `m_animationPath` | `hkStringPtr` |
| 0x58 | `m_behaviorPath` | `hkStringPtr` |
| 0x60 | `m_characterPath` | `hkStringPtr` |
| 0x68 | `m_fullPathToSource` | `hkStringPtr` |
| 0x70 | `m_rootPath` | `hkStringPtr` |

## `hkbCharacterData` and `hkbCharacterStringData`

A character file binds one behavior file to one rig and to the clip list its graph may
play. `hkbCharacterData` derives `hkReferencedObject`; size 176. Abridged to the members
that matter here — OpenSky reads only `m_stringData`, and the neighbours are listed so
the offset is checkable.

| off | field | type |
| --- | --- | --- |
| 0x60 | `m_characterPropertyInfos` | `hkArray<hkbVariableInfo>` |
| 0x80 | `m_characterPropertyValues` | pointer to `hkbVariableValueSet` |
| 0x98 | `m_stringData` | pointer to `hkbCharacterStringData` |
| 0xA8 | `m_scale` | `hkReal` |

`hkbCharacterStringData` derives `hkReferencedObject`; size 192.

| off | field | type |
| --- | --- | --- |
| 0x10 | `m_deformableSkinNames` | `hkArray<hkStringPtr>` |
| 0x20 | `m_rigidSkinNames` | `hkArray<hkStringPtr>` |
| 0x30 | `m_animationNames` | `hkArray<hkStringPtr>` |
| 0x40 | `m_animationFilenames` | `hkArray<hkStringPtr>` |
| 0x50 | `m_characterPropertyNames` | `hkArray<hkStringPtr>` |
| 0x60 | `m_retargetingSkeletonMapperFilenames` | `hkArray<hkStringPtr>` |
| 0x70 | `m_lodNames` | `hkArray<hkStringPtr>` |
| 0x80 | `m_mirroredSyncPointSubstringsA` | `hkArray<hkStringPtr>` |
| 0x90 | `m_mirroredSyncPointSubstringsB` | `hkArray<hkStringPtr>` |
| 0xA0 | `m_name` | `hkStringPtr` |
| 0xA8 | `m_rigName` | `hkStringPtr` |
| 0xB0 | `m_ragdollName` | `hkStringPtr` |
| 0xB8 | `m_behaviorFilename` | `hkStringPtr` |

## File role

`HKBFileRole` is decided from the root container's variant class names, in this order:

| Variant class present | Role |
| --- | --- |
| `hkbProjectData` | project |
| `hkbCharacterData` | character |
| `hkbBehaviorGraph` | behavior |
| `hkaAnimationContainer` with a binding or spline animation object | animation |
| `hkaAnimationContainer` without one | skeleton |
| anything else | unknown |

The animation/skeleton split is a heuristic over the object inventory rather than a
declared field, and it has one known false positive in vanilla — see below.

## Verification

Census of every `.hkx` under `meshes\actors\character\` in the local SSE install
(third-person plus `_1stperson`), 2026-08-03, produced by
`HKBBehaviorCensusRealDataTests` and captured to the gitignored
`logs/hkx-behavior-census.log`. Reproduce with
`make realtest T='HKBBehaviorCensusRealDataTests/censusesCharacterBehaviorFiles()'`.

2,654 files. Every one parses at container level with zero throws, and every one is a
64-bit `hk_2010.2.0-r1` packfile — no tagfile and no other Havok version appears, so the
second container parser the scope warned about is not needed.

Roles: 2,609 animation, 35 behavior, 4 skeleton, 3 character, 3 project. The 35 behavior
files are 18 third-person plus 17 first-person. All three project files
(`defaultmale.hkx`, `defaultfemale.hkx`, `_1stperson\firstperson.hkx`) leave
`m_animationPath`, `m_behaviorPath`, and `m_characterPath` as empty strings and name
exactly one character file each, so paths are relative to the project file's own folder.
Both third-person character files and the first-person one name `Behaviors\0_Master.hkx`
as their behavior entry point.

Every one of the 35 behavior graphs has a name and a root generator, and every root
generator is an `hkbStateMachine` — the node tree is a state machine at the top in all
of them, without exception.

Across the behavior files: 55 distinct object classes, 301 distinct variable names, 1,985
distinct event names. The ten most common classes, as `class objects files`:

```text
hkbStateMachineStateInfo 5269 35
hkbClipGenerator 4975 35
hkbClipTriggerArray 3707 35
hkbVariableBindingSet 3514 35
hkbBlenderGeneratorChild 3358 32
hkbStateMachine 1963 35
hkbStateMachineTransitionInfoArray 1895 31
hkbStateMachineEventPropertyArray 1560 35
hkbBlenderGenerator 1014 32
hkbModifierGenerator 773 28
```

Twelve of the 55 are Bethesda's own `BS*` classes (`BSSynchronizedClipGenerator`,
`BSIsActiveModifier`, `BSiStateTaggingGenerator`, `BSBoneSwitchGenerator`, and others),
so a decoder set covering only stock Havok classes would miss part of the vanilla graph.

The `VariableType` values are confirmed by the vanilla naming convention rather than
taken on trust: in `mt_behavior.hkx`, `bAnimationDriven` and `IsFirstPerson` decode as
bool, `iSyncSprintState` and `iLeftHandType` as int32, and `blendDefault`, `Direction`,
and `SpeedSampled` as real.

Unresolved fields across all 2,654 files: two, both `m_ragdollName` with reason
`noFixup`, on `_1stperson\characters\firstperson.hkx` and `_1stperson\firstperson.hkx`.
First person has no ragdoll, so a null pointer is correct there. No `outOfBounds`,
`sectionMissing`, `negativeCount`, or `undecodableString` miss occurs anywhere, which is
the evidence that every offset in this page is right.

Known role-heuristic false positive:
`meshes\actors\character\animations\byoh\special_childdollplay2.hkx` classifies as
skeleton because its `hkaAnimationContainer` carries no binding or spline animation
object. It is an animation file with an empty clip set, not a rig.
