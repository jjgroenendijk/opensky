---
type: Subsystem
title: Procedural grass
description: Cell-owned GRAS placement, instanced Metal rendering, fade, wind, and controls.
tags: [engine, world, grass, terrain, streaming]
timestamp: 2026-07-22T00:00:00Z
---

# Procedural grass

Milestone 7.5 produces immutable CPU `GrassPlacement` values. Each stores
GRAS identity/model, world position, terrain normal, yaw, scale, vertex color,
wave period, and flags. `CellScene` owns the array + `RenderScene` owns matching
GPU batches -> existing cell load/unload, merge, residency, and cache eviction
own grass too.

Input chain:

```text
LAND BTXT/ATXT coverage -> LTEX repeated GNAM -> GRAS MODL + DATA
```

Record layout + semantic sources: [grass records](/formats/grass.md). Bethesda's
exact candidate lattice and random-number algorithm are not documented in open
specs. OpenSky uses the explicit approximation below; no hidden constants are
claimed as vanilla behavior.

## Placement algorithm

`GrassPlacementBuilder` is a pure pass over one LAND record + decoded indexes:

1. Collect LTEX IDs used by BTXT/ATXT. Resolve their GNAM links and group each
   GRAS with the texture IDs that select it. Sort every FormID before work.
2. Build a square candidate lattice. Requested spacing = max(position range,
   32 game units); axis count = ceil(4096 / spacing), capped at 128. Actual
   spacing evenly covers the cell. Jitter each center by up to half the lesser
   of position range and actual spacing, clamped inside its cell.
3. Seed each candidate from signed cell X/Y, LAND FormID, GRAS FormID, row, and
   column. SplitMix64 supplies platform-stable random values; Swift `Hasher`
   never enters persisted geometry.
4. Sample exact [terrain](/engine/terrain.md) SW-NE triangles for height +
   normal. Hidden CELL XCLC quadrants reject through `TerrainHeightField`.
5. Reconstruct each texture's final coverage using terrain renderer's ordered
   ATXT lerps and triangle interpolation. Accept with probability
   `clamp(density/100) * matchingCoverage`.
6. Reject outside min/max slope. If cell resolves a finite water height, apply
   GRAS water side/distance rule; absent/unknown water policy does not reject.
7. Apply random yaw, height range around scale 1, optional uniform XYZ scale,
   interpolated LAND VCLR, and random darkening from color range. Retain normal
   + fit-to-slope flag for renderer orientation.

Invalid/non-finite controls, zero density, reversed slope range, missing DATA,
or missing MODL produce no placements. Minimum spacing + 128-axis cap bound
malformed input to 16,384 candidates per grass type per cell.

## Determinism + streaming

Seed is stateless per candidate. Rebuilding a cell yields byte-equal placement
order and values regardless of dictionary iteration or neighboring-cell load
order. Neighbor cell coordinates change seed, preventing repeated local
patterns. `CellLoadSummary` reports placements, usable GRAS types, and unusable
GNAM targets. WRLD `No Grass` suppresses the pass. Interiors and LAND-less
cells retain no grass.

## GPU batching + runtime policy

`CellSceneBuilder` groups placements by GRAS FormID, loads each NIF once through
`MeshLibrary`, then expands its meshes into `GrassDrawGroup` values. Group key =
shared mesh + diffuse identity. `RenderScene(merging:)` regroups across resident
cells, so repeated grass types stay one indexed instanced draw per mesh/material.
Cell eviction removes its instances; shared cache residency remains while any
resident cell references the allocation.

Per-instance upload = model/normal matrix, LAND color, stable density key,
motion phase, and GRAS wave period. Fit To Slope maps local +Z to LAND normal;
random yaw then rotates in the tangent plane. Vertex shader bends upper mesh
vertices in weather's published XY wind vector. Wind scale is 0-2. Distance
fade starts at 70% of selected range and feeds alpha-test coverage to avoid a
hard pop.

Per-frame filter order:

1. Stable density key vs 0-100% user scale.
2. Camera distance, clamped to 512-16,384 game units.
3. Frustum against sway-expanded world bounds.
4. Hard 16,384 mesh-instance upload/draw cap.

`GrassDrawStats` separates every rejection bucket. Budget overflow skips only
that frame; fly acceptance requires zero drops. Grass receives sun shadows +
fog. It does not cast shadows or enter point-light selection: small alpha
blades are kept out of dominant shadow/local-light costs.

Main app verification path: `World > Environment > Grass`. Controls toggle
rendering, choose density, draw distance, and wind scale; readout reports
drawn/scene counts, draw calls, distance/frustum rejects, and budget drops.

## Known deviations

+ Candidate lattice, SplitMix64 seed, 32-unit floor, and 128-axis safety cap
  are OpenSky choices. Vanilla lattice, PRNG, boundary ownership, and draw
  thinning are unknown.
+ Position range is treated as spacing + jitter control. Creation Kit explains
  visual spacing/offset behavior, not exact equations.
+ Density is a per-candidate percentage multiplied by reconstructed LTEX
  coverage. Vanilla's coverage sampling/filtering is unknown.
+ Height/color variance use symmetric scale around 1 and one-sided darkening.
  Exact vanilla distributions are unknown.
+ Water enum labels come from xEdit. Boundary comparisons are OpenSky's direct
  interpretation; unknown values pass through.
+ Bend normals are not recomputed after vertex displacement; lighting keeps the
  slope-fitted undeformed mesh normal.
+ Budget order follows deterministic scene/group order, not nearest-first.

## Verification

Synthetic suites prove fixed decode, repeated GNAM, deterministic rebuilds,
neighbor seed changes, full + painted texture coverage, density/slope/water/
hidden-quadrant rejection, variance bounds, WRLD suppression, scene lifetime,
and exact summary accounting.

Placement probe (`GrassRealDataTests`, vanilla Skyrim.esm, 2026-07-22): 27 GRAS and
68 LTEX decoded; 39 GNAM links resolve. `Tamriel (6,-2)` produced 126 CPU
placements across two usable types (56 + 70), zero skipped. Second build was
identical.

Render acceptance (`GrassRenderingAcceptanceRealDataTests`, 640x360): same 126
placements became 126 mesh instances, drawn in 2 calls with zero budget drops.
Grass off/on changed 1,015 pixels; `SkyrimStormSnow` wind 0.698 at 2x scale
changed 44 pixels between exact times 0 and 0.37. Half density drew 67 and
culled 59; minimum distance culled all 126.

Cross-cell fly gate `(6,-2) -> (7,-2) -> (7,-1)`: peak scene carried 11,452
grass mesh instances; 637 visible drew in 3 calls, 9,361 distance-culled, 2,170
frustum-culled, zero budget-dropped. Full streamed run: 5,420 frames at
640x360, 15.90 ms avg / 31.50 ms p95 vs 33.33 ms budget; footprint 738 MB final,
889 MB peak vs 1,024 MB cap. Evidence stays gitignored under `logs/`.
