---
type: Subsystem
title: Terrain walk mode
description: Player capsule movement over streamed LAND height fields with exact triangle
  sampling, gravity, slope limits, and deterministic fixed stepping.
tags: [engine, world, terrain, collision, movement, streaming]
timestamp: 2026-07-19T00:00:00Z
---

# Terrain walk mode

Milestone 4.1 adds physical ground before mesh collision. Fly mode remains default dev
camera; G toggles walk mode. Walk mode owns capsule position + gravity while keeping existing
mouse-look and WASD/Shift input. Q/E vertical input applies only in fly mode.

## Terrain collision surface

`TerrainHeightField` is immutable CPU data retained by each exterior `CellScene` beside its
GPU terrain draws. Source is same data as rendering:

- LAND VHGT -> 33x33 heights, including XCLC hidden-quadrant mask.
- LAND-less cell -> 33x33 constant field at WRLD DNAM default land height, matching rendered
  fallback plane.
- no LAND + no DNAM -> no terrain draw, no collision field.

Each 128-unit quad uses `TerrainMeshBuilder` topology: SW/SE/NE south triangle + SW/NE/NW
north triangle, shared diagonal SW->NE. `sample(at:)` selects triangle, barycentrically
interpolates height, derives face normal from same CCW vertices. It never uses bilinear
interpolation. This matters on saddle quads: rendered diagonal can be height 0 where bilinear
center would be 50.

`CellSceneComposition.sampleTerrain(at:)` maps world XY to resident cell via floor division,
same as `CellGridManager`. Exact east/north border belongs to neighbor; negative coordinates
stay correct. Cell integration makes its field queryable; unload removes it with render data.
Distant LOD never supplies player ground.

## Controller

`WalkController` owns capsule bottom (`feetPosition`), vertical velocity, grounded flag, and
fixed-step residual. Current hardcoded policy (GMST tuning stays backlog):

| Value | Setting |
| --- | ---: |
| Capsule radius | 24 units |
| Capsule height | 128 units |
| Camera eye above bottom | 112 units |
| Walk / run speed | 180 / 360 units/s |
| Gravity | 1,400 units/s² |
| Max slope | 50 degrees |
| Ground snap | 24 units |
| Physics step | 1/120 s |
| Max accepted frame time | 0.1 s |

Look applies once per rendered frame. Movement + gravity consume fixed 1/120 s steps; excess
frame time above 100 ms drops, residual below one step carries forward. Horizontal movement
uses level yaw, independent of look pitch. Diagonals normalize. Shift selects run speed.

Grounded motion rejects candidate terrain whose face normal exceeds slope limit. Allowed
terrain rises snap capsule bottom to rendered plane; gravity + snap keep descending terrain
contact. Airborne player falls until bottom crosses a ground plane, then penetration resolves
to exact sampled height with zero vertical velocity.

`Renderer` owns mode + controller. `GameMetalView` latches G through `CameraInputState`;
renderer drains toggle once, resets controller from current camera when entering walk, then
queries `CellStreamer`'s resident composition before streaming update. First-scene framing or
door camera reseed resets controller pose/grounded state with camera.

## Scope boundary

4.1 ground is exterior terrain only. Static meshes have no collision yet: walls, buildings,
stairs, ceilings, interior floors remain pass-through. NIF bhk decode, per-cell collision
world, capsule collide-and-slide, step response, interior ground land in 4.2-4.4. Capsule
dimensions are already explicit so those stages extend one controller instead of replacing
camera semantics.

## Verification

Synthetic tests:

- `TerrainHeightFieldTests`: flat/negative cells, hidden quadrants, exact east-neighbor border,
  saddle proving triangle-plane vs bilinear result.
- `WalkControllerTests`: capsule eye offset, gravity/ground snap, pitch-independent motion,
  walk/run speeds, slope rejection, 100 ms clamp, fixed-step partition determinism, no-ground
  fall, four resident fields traversed without lost contact.
- `CellSceneTerrainTests`: LAND, XCLC hidden quadrant, DNAM fallback, no-terrain builder paths
  retain collision data matching rendered terrain.
- `CameraInputStateTests`: G request drains exactly once.

Real-install scratch CLI probe decoded LAND for Tamriel `(6,-2)` through `(9,-2)`, retained
four production `TerrainHeightField` values in `CellSceneComposition`, then drove production
`WalkController` east along world Y `-8128`. Three cell borders crossed in 342 100-ms input
frames; every physics step stayed grounded, max capsule-bottom distance from sampled rendered
plane = `0.0` units. Probe code + test-host attempts removed; no game data copied or committed.
