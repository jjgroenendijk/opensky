---
type: File Format
title: NIF mesh (Gamebryo 20.2.0.7, Skyrim SE)
description: On-disk layout of Skyrim SE .nif meshes and how OpenSky reads them.
tags: [format, mesh, geometry, io]
timestamp: 2026-07-10T00:00:00Z
---

# NIF mesh, Gamebryo 20.2.0.7

NetImmerse/Gamebryo scene-graph container holding Skyrim's meshes: node
hierarchy, geometry, materials, collision, animation. SSE meshes are version
20.2.0.7, user version 12, BS stream 100 (LE streamed 83; FO3/NV share the
version with user 11). File = header + block payloads back to back + footer.

Reference: NifTools `nif.xml`
(<https://github.com/niftools/nifxml/blob/develop/nif.xml>) — structs
`Header`, `BSStreamHeader`, `ExportString`, `SizedString`, `Footer`; NifSkope
as ground truth viewer. Impl: `opensky/Formats/NIF/`. All integers
little-endian (header enforces the endian byte).

Doc grows with milestone 2: container (this page), scene graph + geometry
(2.3), materials subset (2.4).

## String framings

| name         | layout                                                      |
| ------------ | ----------------------------------------------------------- |
| HeaderString | text line terminated by `\n` (0x0A), no length prefix       |
| ExportString | uint8 length incl. trailing null, then bytes + null         |
| SizedString  | uint32 length, then bytes, no terminator                    |

Header strings decode lossily (`GameText.decodeLossy`: UTF-8 -> cp1252 ->
ISO 8859-1). Vanilla string tables carry exporter garbage — uninitialized
memory with bytes undefined in cp1252 (observed:
`meshes/dungeons/dwemer/animated/astrolabe/lexiconstand/dwelexiconstandrunes01.nif`,
string `0c 90 29 7b ...`) — and a junk name must not reject the mesh.

## Header — variable size at offset 0

Field order per nif.xml `Header`, restricted to what exists at 20.2.0.7
(`since`/`until` conditions dropped):

| type                 | field            | notes                                    |
| -------------------- | ---------------- | ---------------------------------------- |
| HeaderString         | version line     | `Gamebryo File Format, Version 20.2.0.7` |
| uint32               | version          | 0x14020007 = 20.2.0.7, byte/component    |
| uint8                | endian           | 1 = little; only value accepted          |
| uint32               | user version     | 12 (Skyrim LE + SSE)                     |
| uint32               | block count      |                                          |
| BSStreamHeader       | BS header        | present when user version >= 3           |
| uint16               | block type count |                                          |
| SizedString x count  | block types      | distinct type names ("BSTriShape")       |
| uint16 x block count | type indices     | into block types; bit 15 = PhysX, masked |
| uint32 x block count | block sizes      | byte size per block — skip distance      |
| uint32               | string count     |                                          |
| uint32               | max string len   | write-time hint, ignored                 |
| SizedString x count  | strings          | shared name table, blocks index it       |
| uint32               | group count      |                                          |
| uint32 x count       | groups           |                                          |

BSStreamHeader (Skyrim streams; FO4+ variants with BS version > 130 add/drop
fields and are rejected):

| type         | field          | notes                        |
| ------------ | -------------- | ---------------------------- |
| uint32       | BS version     | 83 = LE, 100 = SSE           |
| ExportString | author         |                              |
| ExportString | process script |                              |
| ExportString | export script  |                              |
| ExportString | max filepath   | only BS version >= 103       |

Block sizes exist since 20.2.0.5 — they are what make a container-level walk
possible without decoding every block type. `NIFHeader.blockDataOffset`
records where block payloads start.

## Block walk

Block payloads follow the header back to back, in table order, with no
per-block framing — block N's bytes span exactly `blockSizes[N]`. `NIFFile`
slices every payload by that size and pairs it with its type name; nothing is
decoded at this layer, so unknown/unneeded types (collision, controllers,
PhysX) are skipped by construction. A block promising more bytes than remain
-> `NIFError.malformed`, walk aborts (caller skips the asset, engine keeps
running).

## Footer

After the last block (nif.xml `Footer`):

| type           | field      | notes                             |
| -------------- | ---------- | --------------------------------- |
| uint32         | root count |                                   |
| int32 x count  | roots      | block indices; -1 = null ref      |

Root refs are stored, not validated — ref resolution belongs to the
scene-graph layer (2.3).

## Scene graph — shared AV-object prefix

Typed block decode starts at 20.2.0.7 with a Skyrim BS stream (83/100) —
other streams shift fields and are rejected (`NIFError.unsupported`). Every
scene-graph object (NiNode lineage, BSTriShape) opens with the same
NiObjectNET + NiAVObject field run (nif.xml; conditions resolved for
BS 83/100: uint32 flags since BS > 26, no property list since BS > 34):

| type           | field         | notes                                     |
| -------------- | ------------- | ----------------------------------------- |
| uint32         | name          | header string table index; -1 = none      |
| uint32         | extra count   | NiExtraData refs follow                   |
| int32 x count  | extra refs    | skipped (M2)                              |
| int32          | controller    | animation, skipped (M2)                   |
| uint32         | flags         |                                           |
| float x 3      | translation   |                                           |
| float x 9      | rotation      | Matrix33, column-major: m11 m21 m31 m12 … |
| float          | scale         | uniform only                              |
| int32          | collision ref | bhk object, recorded not followed (M2)    |

Junk name index -> nil, lenient (same exporter-garbage rationale as header
strings). Local transform composes `T * R * S`, column vectors — matches
`docs/decisions/coordinates.md`. Impl: `NIFObject.swift`.

## NiNode

After the prefix (nif.xml NiNode):

| type           | field       | notes                          |
| -------------- | ----------- | ------------------------------ |
| uint32         | child count |                                |
| int32 x count  | children    | block refs, -1 = empty slot    |
| uint32         | effect count| BS < FO4 only                  |
| int32 x count  | effects     | skipped                        |

`NIFNode.traversedTypes` lists the subclasses decoded with this one layout —
BSFadeNode, BSLeafAnimNode, BSTreeNode, BSOrderedNode, BSMultiBoundNode all
inherit NiNode in nif.xml and only append tail fields, which the size-sliced
block payload bounds away. Selector nodes (NiSwitchNode, NiLODNode) are
excluded on purpose: they draw one child, not all; traversing them would
stack LOD alternatives. Impl: `NIFNode.swift`.

## Observed in vanilla (probe, 2026-07-10)

Container walk over the local install: 22 806 `.nif` across 8 BSAs
(Meshes0/1, Animations, _ResourcePack, cc*) — all parsed, zero throws. All
are version 20.2.0.7, user version 12; BS stream 100 except a single 83
(LE-era leftover). 143 distinct block types.

Top types, the coverage list for 2.3/2.4 (counts = block instances across
all files):

| count   | type                       | layer                        |
| ------- | -------------------------- | ---------------------------- |
| 102 444 | NiNode                     | scene graph (2.3)            |
| 74 955  | BSLightingShaderProperty   | materials (2.4)              |
| 64 157  | BSShaderTextureSet         | materials (2.4)              |
| 61 617  | BSTriShape                 | geometry (2.3)               |
| 38 253  | NiFloatInterpolator        | animation — skipped          |
| 36 640  | NiAlphaProperty            | materials (2.4)              |
| 35 335  | NiFloatData                | animation — skipped          |
| 27 805  | NiSkinData/NiSkinPartition | skinning — skipped for M2    |
| 21 675  | BSDynamicTriShape          | skinned geometry — skipped   |
| 18 839  | BSFadeNode                 | NiNode subclass, same layout |
| 13 736  | bhkCollisionObject         | collision — skipped for M2   |

Statics for M2 need: NiNode (+ BSFadeNode as root), BSTriShape,
BSLightingShaderProperty, BSShaderTextureSet, NiAlphaProperty. Everything
Havok (`bhk*`), particle (`*PSys*`), controller/interpolator (animation) and
skinning gets walked over by size.
