---
type: Subsystem
title: Procedural grass placement
description: Deterministic cell-owned GRAS placement from LAND texture coverage.
tags: [engine, world, grass, terrain, streaming]
timestamp: 2026-07-22T00:00:00Z
---

# Procedural grass placement

Milestone 7.5.1 produces immutable CPU `GrassPlacement` values. Each stores
GRAS identity/model, world position, terrain normal, yaw, scale, vertex color,
wave period, and flags. `CellScene` owns the array -> existing cell
load/unload lifetime owns grass too. M7.5.2 consumes it for mesh loading,
instanced Metal draws, weather wind, distance fade, and app controls.

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
+ Terrain-normal fit is retained but not applied until M7.5.2 renderer work.

## Verification

Synthetic suites prove fixed decode, repeated GNAM, deterministic rebuilds,
neighbor seed changes, full + painted texture coverage, density/slope/water/
hidden-quadrant rejection, variance bounds, WRLD suppression, scene lifetime,
and exact summary accounting.

Real probe (`GrassRealDataTests`, vanilla Skyrim.esm, 2026-07-22): 27 GRAS and
68 LTEX decoded; 39 GNAM links resolve. `Tamriel (6,-2)` produced 126 CPU
placements across two usable types (56 + 70), zero skipped. Second build was
identical. This proves internal consistency + plausible nonzero density, not
visual parity with vanilla; M7.5.2's offscreen/app gate owns visual comparison.
Evidence stays gitignored under `logs/`.
