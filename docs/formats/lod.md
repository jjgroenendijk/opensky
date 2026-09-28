---
type: File Format
title: Skyrim SE distant LOD
description: lodsettings, terrain BTR, object BTO, and tree LST and BTT layouts.
tags: [format, lod, terrain, tree, nif, rendering]
---

# Distant LOD

LOD (level of detail) files hold simple terrain, objects, and trees for the land beyond the
loaded cells.

Sources:

- xEdit `dev-4.1.6` [`wbLOD.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbLOD.pas)
  (`TwbLodSettings.LoadFromData`, block anchors, tree paths).
- xEdit [`LODGen.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Build/Edit%20Scripts/LODGen.pas)
  for how terrain and object LOD files are generated.
- NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml):
  `BSMultiBoundNode`, `BSMultiBound`, `BSMultiBoundAABB`, `BSSubIndexTriShape`,
  `BSGeometrySegmentData`.
- UESP [LOD Settings File Format](https://en.uesp.net/wiki/Tes5Mod:LOD_Settings_File_Format).

`.btr` and `.bto` are NIF files in a shape set by the generator tool. Bethesda has not
published them. So the parsers check every count and range.

`openskycli lod --worldspace Tamriel` parses every LOD file of a worldspace and reports
failures. On vanilla there are none.

## lodsettings

Path: `lodsettings/<worldspace editor ID>.lod`. Exactly 16 bytes, little-endian:

| Offset | Type | Field |
| --- | --- | --- |
| 0 | int16 | South-west origin cell X |
| 2 | int16 | South-west origin cell Y |
| 4 | int32 | Worldspace size in cells |
| 8 | int32 | Lowest LOD level |
| 12 | int32 | Highest LOD level |

Levels double from lowest to highest. For vanilla `tamriel.lod`: origin (-96, -96), size 256,
levels 4, 8, 16, 32.

The block that holds cell `C` at level `N` starts at:

```text
origin + floor((C - origin) / N) * N
```

Use floor division. Swift's `/` rounds toward zero, which puts cells west or south of the
origin in the wrong block. Example: origin -96, level 4, cell -97 is in block -100, not -96.

## Terrain BTR

```text
meshes/terrain/<ws>/<ws>.<level>.<x>.<y>.btr
textures/terrain/<ws>/<ws>.<level>.<x>.<y>.dds
textures/terrain/<ws>/<ws>.<level>.<x>.<y>_n.dds
```

`(x, y)` is the south-west cell of the block. Level `N` covers N x N cells. Terrain vertices
are local to the block, so they are moved by `(x * 4096, y * 4096, 0)`. Example:
`tamriel.4.4.-4.btr` has one `land` shape with local bounds (0, 0) to (16384, 16384).

A terrain file usually has two `BSMultiBoundNode` children: `chunk` holds the land, and
`WATER` holds a water shape. OpenSky drops the `WATER` part and draws water itself.

Vanilla terrain color atlases are xRGB8888 DDS with full mip chains (see
[DDS](/formats/dds.md)). They upload as sRGB BGRA8. Normal atlases are DXT5 and linear.

Blocks added on top of the shared [NIF](/formats/nif.md) layouts:

| Block | Data after the inherited part |
| --- | --- |
| `BSMultiBoundNode` | NiNode fields, int32 multi-bound ref, uint32 culling mode |
| `BSMultiBound` | int32 data ref |
| `BSMultiBoundAABB` | float3 center, float3 extent (not negative) |

## Object BTO

```text
meshes/terrain/<ws>/objects/<ws>.<level>.<x>.<y>.bto
textures/terrain/<ws>/objects/<ws>.objects.dds
textures/terrain/<ws>/objects/<ws>.objects_n.dds
```

Vanilla object levels are 4, 8, and 16. All blocks share one atlas.

Unlike BTR, vanilla BTO vertices are already in world space. Example: `tamriel.4.4.-4.bto`
has bounds near the world position of cell (4, -4). Moving it by the file name again would
place objects twice as far. So OpenSky does not move BTO geometry.

The object color atlas is RGBA8888 with stored alpha. The normal atlas is DXT5.

An SSE `BSSubIndexTriShape` is a full `BSTriShape`, then:

| Type | Field | Check |
| --- | --- | --- |
| uint32 | Segment count | Each segment needs 9 more bytes |
| uint8, repeated | Flags | Kept, not used |
| uint32, repeated | Start index | Into the flat triangle index list |
| uint32, repeated | Triangle count | `start + count * 3 <= index count` |

OpenSky checks the segments but draws the whole shape. Particle data in the `BSTriShape` part
is skipped by its declared size first.

## Tree LST and BTT

Tree LOD uses one type list, one atlas, and level-4 placement blocks:

```text
meshes/terrain/<ws>/trees/<ws>.lst
meshes/terrain/<ws>/trees/<ws>.4.<x>.<y>.btt
textures/terrain/<ws>/trees/<ws>treelod.dds
```

`LST` (from xEdit `TwbLodTES5TreeType.LoadFromData`): an int32 count, then 32-byte records.

| Bytes | Type | Field |
| --- | --- | --- |
| 4 | int32 | Type index, used by BTT |
| 8 | float32 x 2 | Billboard width, height |
| 16 | float32 x 4 | Atlas UV min X, min Y, max X, max Y |
| 4 | uint32 | Unknown, kept |

`BTT` (from xEdit `TwbLodTES5TreeBlock.LoadFromData`): an int32 group count. Each group is an
int32 type index and an int32 reference count, then 32-byte references.

| Bytes | Type | Field |
| --- | --- | --- |
| 12 | float32 x 3 | World position |
| 4 | float32 | Rotation around +Z, radians |
| 4 | float32 | Uniform scale |
| 4 | uint32 | Source FormID |
| 8 | uint32 x 2 | Unknown, kept |

The parser rejects impossible counts, sizes or transforms that are not finite, duplicate LST
indices, BTT type indices that LST does not have, and extra bytes. Atlas UVs may go a little
outside 0 to 1, because vanilla padding does. They only need to be finite and ordered.

A tree billboard is two double-sided planes that cross at 90 degrees. DynDOLOD's
[Tree LOD](https://dyndolod.info/Help/Tree-LOD) page confirms this. OpenSky builds the planes
from the LST size and UVs, alpha-tests the atlas, and places them with the BTT transform.
