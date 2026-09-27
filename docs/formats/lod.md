---
type: File Format
title: Skyrim SE distant LOD
description: lodsettings, terrain BTR, object BTO, and tree LST and BTT layouts.
tags: [format, lod, terrain, tree, nif, rendering]
---

# Skyrim SE distant LOD

LOD (level of detail) files hold simple terrain, objects, and trees for the area beyond the
loaded cells. See [distant LOD](/engine/distant-lod.md) for how OpenSky draws them.

References:

- xEdit `dev-4.1.6`
  [`wbLOD.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbLOD.pas)
  (`TwbLodSettings.LoadFromData`, block positions, tree paths).
- xEdit generator
  [`LODGen.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Build/Edit%20Scripts/LODGen.pas)
  for the terrain and object file conventions.
- NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml):
  `BSMultiBoundNode`, `BSMultiBound`, `BSMultiBoundAABB`, `BSSubIndexTriShape`,
  `BSGeometrySegmentData`.
- UESP [LOD Settings File Format](https://en.uesp.net/wiki/Tes5Mod:LOD_Settings_File_Format).

`.btr` and `.bto` are NIF files in a shape that the LOD generator defines. Bethesda did not
publish a specification. So OpenSky checks every count and range, and the whole vanilla set
was parsed to confirm the layout. `openskycli lod --worldspace Tamriel` parses every LOD
file of a worldspace.

## lodsettings

Path: `lodsettings/<worldspace editor ID>.lod`. Exactly 16 bytes, little-endian:

| Offset | Type | Field |
| --- | --- | --- |
| 0 | int16 | South-west origin cell X |
| 2 | int16 | South-west origin cell Y |
| 4 | int32 | Worldspace size in cells |
| 8 | int32 | Lowest LOD level |
| 12 | int32 | Highest LOD level |

Levels double from the lowest to the highest. At level `N`, the block that holds cell `C`
starts at:

`origin + floor((C - origin) / N) * N`

Use floor division. Swift's `/` rounds toward zero, which gives the wrong block for cells
west or south of the origin. Vanilla `tamriel.lod`: origin (-96, -96), size 256, levels 4,
8, 16, 32.

## Terrain BTR

```text
meshes/terrain/<ws>/<ws>.<level>.<x>.<y>.btr
textures/terrain/<ws>/<ws>.<level>.<x>.<y>.dds
textures/terrain/<ws>/<ws>.<level>.<x>.<y>_n.dds
```

`(x, y)` is the south-west cell of the block. A level N block covers N x N cells. Terrain
vertices are relative to the block, so OpenSky moves them by `(x * 4096, y * 4096, 0)`. For
example, `tamriel.4.4.-4.btr` has a `land` shape with bounds (0, 0) to (16384, 16384).

A terrain file usually has two `BSMultiBoundNode` children: `chunk` holds the land, and
`WATER` holds a water shape.

The vanilla diffuse maps at all levels are 32-bit xRGB8888 DDS with full mip chains. The
normal maps are DXT5. See [DDS](/formats/dds.md).

Blocks added on top of the shared [NIF](/formats/nif.md) layouts:

| Block | Data after the inherited part |
| --- | --- |
| `BSMultiBoundNode` | `NiNode` children and effects, int32 multi-bound ref, uint32 culling mode |
| `BSMultiBound` | int32 data ref |
| `BSMultiBoundAABB` | float3 center, float3 extent (not negative) |

## Object BTO

```text
meshes/terrain/<ws>/objects/<ws>.<level>.<x>.<y>.bto
textures/terrain/<ws>/objects/<ws>.objects.dds
textures/terrain/<ws>/objects/<ws>.objects_n.dds
```

Vanilla object levels are 4, 8, and 16. All blocks share one texture atlas. The diffuse
atlas is RGBA8888 with real alpha. The normal atlas is DXT5.

Unlike BTR, BTO vertices are already in world space. For example, `tamriel.4.4.-4.bto` has
its bounds near the world origin of cell (4, -4). Moving it by the file name position would
move it twice.

A Skyrim SE `BSSubIndexTriShape` is a full `BSTriShape`, then:

| Type | Field | Check |
| --- | --- | --- |
| uint32 | Segment count | Each segment needs 9 more bytes |
| uint8 per segment | Flags | Kept, not used |
| uint32 per segment | Start index | Into the triangle index list |
| uint32 per segment | Triangle count | `start + count * 3 <= index count` |

OpenSky reads and checks the segments, but draws the whole shape. Particle bytes in the
`BSTriShape` part are skipped by their stated size first.

## Trees: LST and BTT

```text
meshes/terrain/<ws>/trees/<ws>.lst
meshes/terrain/<ws>/trees/<ws>.4.<x>.<y>.btt
textures/terrain/<ws>/trees/<ws>treelod.dds
```

There is one type list, one atlas, and one BTT per level 4 block. The atlas is BGRA8888.

LST (xEdit `TwbLodTES5TreeType.LoadFromData`): an int32 count, then 32-byte entries:

| Bytes | Type | Field |
| ---: | --- | --- |
| 4 | int32 | Type index, used by BTT |
| 4 + 4 | float32 | Billboard width, height |
| 4 x 4 | float32 | Atlas UV min X, min Y, max X, max Y |
| 4 | uint32 | Unknown, kept |

BTT (xEdit `TwbLodTES5TreeBlock.LoadFromData`): an int32 group count. Each group is an
int32 type index and an int32 reference count, then 32-byte references:

| Bytes | Type | Field |
| ---: | --- | --- |
| 12 | 3 x float32 | World position |
| 4 | float32 | Rotation around +Z, radians |
| 4 | float32 | Uniform scale |
| 4 | uint32 | Source FormID |
| 8 | 2 x uint32 | Unknown, kept |

OpenSky rejects impossible counts, sizes or transforms that are not finite or not valid,
duplicate LST indices, BTT type indices not in the LST, and extra bytes at the end. Atlas
UVs may go a little outside 0...1, because the vanilla padding does. So only finite,
ordered bounds are required.

The DynDOLOD page [Tree LOD](https://dyndolod.info/Help/Tree-LOD) confirms that a tree
billboard is two double-sided planes that cross at 90 degrees. OpenSky builds these planes
from the LST size and UVs, uses an alpha test on the atlas, and places them with the BTT
data.
