---
type: Decision
title: Coordinate systems, units, matrix conventions
description: World space stays Skyrim Z-up right-handed at native units; view/projection
  convert to Metal NDC. Fixes matrix convention, winding/cull, near/far, REFR euler.
tags: [decision, coordinates, math, rendering]
timestamp: 2026-07-10T00:00:00Z
---

# Coordinates + units

Blocker decision for all NIF + renderer work (milestone 2). Binding for every subsystem
that touches positions, rotations, or projection.

## Decision

World space = Skyrim's, untouched. Right-handed, Z-up (+X east, +Y north, +Z up),
1 unit = 1.428 cm (~70 units/m, exterior cell = 4096 units ~ 58.5 m). Mesh vertices,
REFR placements, terrain heights flow through the engine verbatim — no per-asset rewrite,
no unit scaling. View + projection matrices alone convert to Metal clip space.

Why: one conversion point instead of N asset rewrites. Parsed data stays byte-comparable
to disk (probe/debug friendly), community docs (UESP, xEdit) stay directly applicable,
no drift risk between converted + unconverted assets.

Refs: Creation Kit wiki "Unit" (1 unit = 0.0142875 m, cell = 4096 units);
UESP Skyrim Mod:Mod File Format/REFR (DATA = 6 floats, radians).

## Matrix convention

- `simd` `float4x4`, column-major, column vectors: transform = `M * v`.
- Composition right-to-left: `world = T * R * S`, `clip = P * V * M * v`.
- All MatrixMath helpers follow this; anything else is a bug.

## View + projection (basis change lives here)

- Eye space: Metal-conventional — +x right, +y up, camera looks down −z.
- `MatrixMath.lookAt(eye:target:up:)` builds the view matrix directly from Z-up world
  vectors; pass world up = +Z. Proper rotation + translation (det +1, no reflection) —
  the Z-up -> y-up basis change falls out of the RH orthonormal basis construction.
- `MatrixMath.zUpToYUp` = constant basis-change matrix (x,y,z) -> (x,z,−y), det +1.
  For fixed debug cameras + tests; `lookAt` already subsumes it.
- Projection: existing `MatrixMath.perspective` — RH, clip z in [0,1] (Metal NDC),
  `w = −z_eye`. Unchanged.

## Triangle winding + cull mode

Decision: `frontFacingWinding = .counterClockwise`, `cullMode = .back`. Observed, no
longer provisional.

Authoring rule (world space): a face is front when its vertices wind counter-clockwise
seen from outside — right-hand-rule triangle normal points outward. Matches Gamebryo/NIF
content (OpenMW renders the same meshes in OpenGL with CCW front) and OpenSky demo
geometry.

Observed 2026-07-10 (2.6 demo scene, single-sided ground plane): under our
proper-rotation view + RH Metal projection, CCW-from-outside geometry reaches Metal's
rasterizer classified counter-clockwise — with the earlier provisional `.clockwise`
front the plane culled away entirely (interior faces of closed boxes masked the bug;
a single-sided quad exposed it). The original D3D-window-coords reasoning was off by
exactly one y-flip: Metal evaluates winding in NDC orientation (y-up), not framebuffer
y-down.

Verified against vanilla content 2026-07-17 (2.7, `WhiterunExterior06` offscreen
render): wall segments, towers and building LODs all render solid from outside —
nothing inside-out. Decision final.

## Near/far planes at Skyrim scale

M2 defaults: near = 10 units (~14 cm), far = 65 536 units (16 cells, ~936 m).

- Depth attachment is `depth32Float`; near/far ratio 6.5e3 is comfortable. Do not
  shrink near below ~1 unit — that, not far, destroys precision.
- M3 (distant LOD, far in the hundreds of cells) revisit: reverse-Z is the known fix,
  note only, not built now.

## REFR euler rotation — order + sign

Storage (observed + UESP REFR): DATA = posX, posY, posZ (units), rotX, rotY, rotZ,
radians, world axes.

Probe observations, vanilla `Skyrim.esm`, 2026-07-10 (throwaway probe per AGENTS.md —
not committed): 6 372 Tamriel exterior cells, 236 187 temporary REFRs:

- Every position inside its cell's `[grid*4096, grid*4096+4096)` X/Y square ->
  confirms +X/+Y axis mapping, 4096-unit cell, grid labels.
- Every rotation component within [−2π, 2π]; none outside -> radians, not degrees.
- 35% of refs rotate about Z only; X/Y components cluster near 0 (terrain-tilt sized) ->
  Z is the yaw/up axis.
- `WhiterunExterior01` at grid (4,−3), matching UESP's documented Whiterun location.

Convention (with our CCW-positive rotation helpers):

```text
R = Rz(−rotZ) * Ry(−rotY) * Rx(−rotX)
world = T(position) * R * S(scale)      // XSCL uniform scale, default 1
```

Angles negated: Bethesda angles turn clockwise viewed from the positive axis end
(left-handed sign in a RH space). Order Z·Y·X with X innermost. Source: community
consensus — xEdit displays REFR angles as clockwise degrees; OpenMW (GPL clean-room
engine for the same Gamebryo lineage) applies negated eulers in this order.

Verified visually 2026-07-17 (2.7, `WhiterunExterior06` offscreen render): city-wall
segments placed at differing yaws join into one continuous curved run — wrong sign
would mirror/scatter the joints, wrong order would tilt segments. Decision final.

`MatrixMath.placement(position:rotation:scale:)` implements exactly this compose.
