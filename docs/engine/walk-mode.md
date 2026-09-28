---
type: Subsystem
title: Walk mode
description: The fixed-step player capsule over terrain and mesh collision, its settings, who
  owns horizontal and vertical motion when a behavior graph is attached, gaits, jump, swim,
  the ground material, collision response, and the walk route benchmark.
tags: [engine, world, terrain, collision, movement, streaming, locomotion]
---

# Walk mode

Fly mode is the default developer camera. `G` cycles to walk mode (first person) and third person.
In walk mode a player capsule owns the position and gravity. Mouse look and WASD with Shift work as
in fly mode. `Q` and `E` move up and down only in fly mode. The camera modes and the player body
are on the [player camera and body](/engine/player-camera.md) page.

## Terrain collision

Each exterior cell keeps an immutable height field on the CPU, beside its terrain draws. It comes
from the same data as rendering ([terrain](/engine/terrain.md)):

- `LAND` `VHGT` gives 33x33 heights, with the `XCLC` hidden quadrant mask.
- A cell with no `LAND` gets a flat 33x33 field at the `WRLD` `DNAM` default land height, like the
  drawn fallback plane.
- No `LAND` and no `DNAM` gives no terrain draw and no collision.

Each 128-unit quad uses the same triangles as the terrain mesh: a south triangle SW, SE, NE and a
north triangle SW, NE, NW, sharing the SW to NE diagonal. A sample picks the triangle, interpolates
height with barycentric weights, and takes the face normal from the same vertices. It never uses
bilinear interpolation. On a saddle quad this matters: the drawn diagonal can be at height 0 where
a bilinear center would be 50.

A ground sample also names the ground's material. Each exterior cell resolves its `LAND` textures
into one `MATT` per terrain vertex: the heaviest-weighted texture at that vertex, from the same
ordered blends the terrain shader uses. A sample reports the material of the nearest of the quad's
four corners. Height blends across a face, but material does not: a surface is one material or the
other ([material types](/formats/material-type.md)).

A world XY maps to its loaded cell by floor division. The exact east or north border belongs to
the neighbor. Distant LOD never gives the player ground.

## Settings

The controller owns the capsule bottom (feet), vertical velocity, the grounded flag, and the
leftover step time. Its settings are fixed when the renderer is set up, from the
[game settings](/formats/gmst.md) and movement types:

| Setting | Value |
| --- | --- |
| Capsule radius | 24 units |
| Capsule height | 128 units |
| Eye above feet | 112 units |
| Walk speed | `fMoveCharWalkBase`, fallback 100 units/s |
| Run speed | `fMoveCharRunBase`, fallback 370 units/s |
| Sprint speed | `NPC_Sprinting_MT` `SPED` forward run, 500 units/s |
| Sneak speed | `NPC_Sneaking_MT` `SPED` forward walk, 47.2 units/s |
| Swim speed | `NPC_Swimming_MT` `SPED` forward walk, 80.1 units/s |
| Jump takeoff | `sqrt(2 g fJumpHeightMin)`, 461.3 units/s at 76 units |
| Swim vertical limit | 200 units/s |
| Gravity | 1,400 units/s² |
| Largest walkable slope | 50 degrees |
| Ground snap | 24 units |
| Step height | 32 units. No confirmed Skyrim SE game setting |
| Physics step | 1/120 s |
| Longest accepted frame | 0.1 s |

Movement uses fixed steps. Frame time over 100 ms is dropped, and a remainder under one step carries
over. Horizontal movement uses the level yaw, not the pitch. Diagonals are normalized.

Sprint, sneak, and swim have no game setting. They come from the `MOVT` movement types
([records](/formats/records.md)), found by editor ID across the load order, so a mod that changes
sneaking changes it here. `fMoveCharRunBase` is not in `Skyrim.esm` and falls back to 370, which is
exactly what `NPC_Default_MT` gives as its forward run.

Jump takeoff is derived: `fJumpHeightMin` (76 units in `Skyrim.esm`) is a height, and reaching
height `h` under gravity `g` needs `sqrt(2 g h)`. So the top of the jump stays at the written height
if either value changes.

## Input

| Key | Action | Vanilla binding |
| --- | --- | --- |
| W, A, S, D | Move | Same |
| Shift (hold) | Run | OpenSky. Vanilla walks by default and toggles with Caps Lock |
| Option (hold) | Sprint | Alt |
| C | Sneak, a toggle | Ctrl |
| Space | Jump | Same |
| G | Camera mode: fly, first person, third person | OpenSky developer control. Vanilla uses F for first and third |
| F | Use | E |

macOS uses Control-click as the secondary click, so Control cannot be held during mouse look. That
is why sneak moved. Sneak is a mode, not a held key, so it stays on when the pointer is released.
Sprint and a pending jump are dropped. Every binding is listed on the World > Player & Locomotion
panel.

## Who moves the capsule

One bridge is where input, the behavior graph, and the controller meet. Its rules:

- Horizontal motion has exactly one source per fixed step. The bridge picks it and gives the
  controller a displacement, not a velocity or an acceleration. With a planner attached, the
  controller adds no horizontal motion of its own, so no axis is integrated twice.
- Vertical motion belongs to the controller: gravity, ground snap, step support, and the slope rule.
  The bridge may add one jump impulse and may say a step is under water. It cannot integrate height.
- The loop closes through the controller. The feet position, vertical velocity, and grounded flag
  go back to the bridge on the next step and become graph variables.

The horizontal source is the graph's own root motion when the data has any, and the gait speed
otherwise. Vanilla always takes the second path, and that is measured: none of the 2,654 HKX files
under `meshes\actors\character\` contains an `hkaAnimatedReferenceFrame`, and every
`hkaSplineCompressedAnimation` in the movement clips leaves `m_extractedMotion` null. Skyrim's
movement clips animate in place, and the engine supplies the travel. Driving `mt_behavior.hkx` for
three seconds of walking moves the root bone 0.04 units in total. That is jitter, not movement. The
root motion path stays, so data that does carry extracted motion drives the capsule.

The path is chosen from the data, not from a measured distance. The clip evaluator reports root
travel only for a clip whose file has extracted motion ([hka animation](/formats/hka-animation.md)).
A clip with extracted motion that stands still for a step keeps control and reports no travel. An
in-place clip never gains control, however far its root bone drifts. Both hold through a blend.

A speed threshold on the root bone did not work. It was 10 units per second, against a measured
average jitter of about 1. But the test runs per 1/120 s step, so one step where the root moves
0.09 units reads as 10.8 units per second. A few hundred steps of a test route took the wrong path,
and one moved the capsule backwards.

A paused frame does nothing: no graph update, no event, and no movement
([menu mode](/engine/menu-mode.md)).

## Gaits, jump, and swim

Sneak wins over sprint, which wins over run. Swimming replaces all three. Crouching cancels a
sprint. The gait sets the speed and the graph's `Speed` variable.

The jump key holds one request until a fixed step uses it. A jump needs solid ground. In the air the
request is dropped, not queued, so a held key cannot jump again on landing. Takeoff sets the
vertical velocity, clears grounded and step support, and raises `JumpUp`. `JumpFall` is raised when
the capsule leaves the ground without jumping, and `JumpLand` when the controller reports ground
again.

Water height is `CELL` `XCLW` over the worldspace default ([sky and water](/engine/sky-water.md)).
Interiors report none: a vanilla interior places its water as geometry, not as a plane.

Swimming starts when the feet are 90 units under the surface, and stops when they rise to within 70.
The two values differ so a capsule bobbing at the edge cannot flip every step. Both are OpenSky's,
measured against the capsule: the player swims at about chest depth and wades above that. No game
setting gives either. While swimming there is no gravity, snap, or step support. The capsule moves
toward the depth that puts its eye at the surface, or up (jump) and down (sneak) on request, limited
to 200 units per second. A swimmer resting on a shallow bottom counts as grounded, so it can walk
out.

## Ground material

The controller reports the `MATT` of the surface underfoot. It is empty in the air, and on a surface
with no material. Three paths set it, one for each way the capsule becomes grounded:

- Snapping to terrain: the material from the ground sample. Terrain wins over a mesh contact here,
  because this path put the feet down.
- A walkable capsule contact: the material of the flattest walkable contact. A floor and the wall
  beside it can both touch the capsule, and only the floor is stood on. A contact with no material
  is skipped, so a decoration with no material does not silence the step.
- Step support: the material the step probe landed on, so a wooden stair sounds like wood.

[Footstep sounds](/engine/footstep-sounds.md) read it once per frame.

## Collision response

On terrain, grounded motion refuses a face steeper than the slope limit. An allowed rise snaps the
feet to the drawn surface. Gravity and snap keep contact on the way down. A falling player stops
when the feet cross the ground, at the exact sampled height with zero vertical velocity.

Against meshes, the capsule queries the loaded cells' trees with the swept capsule's box
([static collision](/engine/collision-world.md)). Each step is split into moves no longer than half
the capsule radius, so thin surfaces cannot be skipped. The narrow phase handles triangle meshes,
convex hull faces, boxes, spheres, and capsules. Up to eight of the deepest contacts push the
capsule out. The rest of the motion stays, so the capsule slides along a wall. Steep normals block
horizontally. Walkable normals ground the capsule. A downward contact stops falling, and an upward
one stops rising.

A blocked grounded move gets one step attempt. A probe looks ahead and down for a surface no
steeper than the slope limit, so a riser cannot count as support. The controller checks for the
full step height of clearance, moves over the obstacle, and keeps the tread as support until the
capsule's center reaches it. A higher obstacle or a low ceiling fails the check, and the wall
response wins. The same probe crosses from terrain to a mesh stair.

A door or the first scene placement resets the whole controller state before the next step. Moving
bodies collide through the same query ([dynamic bodies](/engine/dynamic-bodies.md)).

## The walk route benchmark

`openskycli bench --walk-path` runs a fixed route. Fixed 1/30 s input frames drive 1/120 s steps
from Tamriel cell `(6,-2)` across streamed terrain to Chillfurrow Farm `(7,-3)`, around fixed
waypoints, with small fixed sidesteps when a small static blocks progress. It requires:

- grounded travel with no penetration or fall-through on any active frame;
- at least 16 units of climb on the outside stair before door `0001633D`;
- interior `CELL` `00016204`, two waypoints inside covering 80% of 192 units, and the way back out
  through the paired door `000163A8` to cell `(7,-3)` and the saved return pose;
- a mean physics frame time of at most 33.33 ms (30 fps) in every build. The p95 limit is 33.33 ms
  in Release and two intervals (66.67 ms) in Debug, because the offscreen loop carries Debug
  runtime and scheduler noise. A given `--budget-ms` applies strictly to both.
