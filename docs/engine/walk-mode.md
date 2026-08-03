---
type: Subsystem
title: Terrain walk mode
description: Fixed-step player capsule over streamed terrain and static mesh collision with
  gravity, collide-and-slide, slope limits, bounded step response, and the movement-authority
  split that lets a behavior graph drive it.
tags: [engine, world, terrain, collision, movement, streaming, locomotion, milestone-14]
timestamp: 2026-08-03T00:00:00Z
---

# Terrain walk mode

Milestone 4.1 adds physical ground before mesh collision. Fly mode remains default dev
camera; G toggles walk mode. Walk mode owns capsule position + gravity while keeping existing
mouse-look and WASD/Shift input. Q/E vertical input applies only in fly mode.

Milestone 14 item 14.5 adds the other half: sprint, sneak, jump, and swim, and the rule that
decides who moves the capsule once a
[behavior graph](/engine/behavior-runtime.md) is attached to it.

## Contents

* [Terrain collision surface](#terrain-collision-surface)
* [Controller](#controller)
* [Input](#input)
* [Movement authority](#movement-authority)
* [Gaits](#gaits)
* [Jump](#jump)
* [Swim](#swim)
* [Response](#response)
* [Scope boundary](#scope-boundary)
* [Verification](#verification)
* [Milestone acceptance route](#milestone-acceptance-route)

## Terrain collision surface

`TerrainHeightField` is immutable CPU data retained by each exterior `CellScene` beside its
GPU terrain draws. Source is same data as rendering:

* LAND VHGT -> 33x33 heights, including XCLC hidden-quadrant mask.
* LAND-less cell -> 33x33 constant field at WRLD DNAM default land height, matching rendered
  fallback plane.
* no LAND + no DNAM -> no terrain draw, no collision field.

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
fixed-step residual. It also owns one immutable `PlayerMovementConfiguration`, resolved
before renderer setup from the selected [GMST movement settings](/formats/gmst.md):

| Setting | Value |
| --- | --- |
| Capsule radius | 24 units |
| Capsule height | 128 units |
| Camera eye above bottom | 112 units |
| Walk speed | `fMoveCharWalkBase`, fallback 100 units/s |
| Run speed | `fMoveCharRunBase`, fallback 370 units/s |
| Sprint speed | `NPC_Sprinting_MT` SPED forward run, 500 units/s |
| Sneak speed | `NPC_Sneaking_MT` SPED forward walk, 47.2 units/s |
| Swim speed | `NPC_Swimming_MT` SPED forward walk, 80.1 units/s |
| Jump takeoff | `sqrt(2 g fJumpHeightMin)`, 461.3 units/s at 76 units |
| Swim vertical clamp | 200 units/s |
| Gravity | 1,400 units/s² |
| Max slope | 50 degrees |
| Ground snap | 24 units |
| Step height | 32 units, explicit fallback; no confirmed Skyrim SE GMST |
| Physics step | 1/120 s |
| Max accepted frame time | 0.1 s |

Look applies once per rendered frame. Movement + gravity consume fixed 1/120 s steps; excess
frame time above 100 ms drops, residual below one step carries forward. Horizontal movement
uses level yaw, independent of look pitch. Diagonals normalize. Shift selects run speed.

The three gaits added by item 14.5 have no GMST. They come from the
[MOVT movement types](/formats/records.md) the player's gaits are authored in, resolved by
editor ID across the whole load order, so a mod that retunes sneaking retunes it here.
`fMoveCharRunBase` is absent from `Skyrim.esm` and falls back to 370 units/s, which is
exactly what `NPC_Default_MT` authors as its forward run — the fallback and the data agree.

Jump takeoff is derived rather than tuned: `fJumpHeightMin` (76 units in `Skyrim.esm`) is a
height, and reaching height `h` under constant gravity `g` needs `sqrt(2 g h)`. The apex
therefore stays on the authored number if either the setting or the gravity constant changes.

## Input

| Key | Action | Vanilla binding |
| --- | --- | --- |
| W/A/S/D | Move | same |
| Shift (hold) | Run | OpenSky; vanilla walks by default and toggles with Caps Lock |
| Option (hold) | Sprint | Alt |
| C | Sneak, a toggle rather than a held key | Ctrl |
| Space | Jump | same |
| G | Fly/walk toggle | OpenSky dev control |
| F | Activate | E |

Sneak deviates because macOS reserves Control-click as the secondary click, so Control cannot
be held through a mouse-look session. Sneak is a mode rather than a held key, so it
deliberately survives capture loss: releasing the pointer must not stand the player up, while
a held sprint and a pending jump are both dropped.

Every one of these bindings is listed on the `World > Player & Locomotion` panel, which is
what keeps them inside the app-ui rule against unadvertised keystrokes. The provider seam
(`PlayerLocomotionControlProviding`) lands with item 14.5; the panel itself lands with the
locomotion gate.

## Movement authority

`LocomotionBridge` is the one place player input, the behavior graph, and the controller
meet. The rule it enforces:

* **Horizontal motion has exactly one source per fixed step.** The bridge picks it and hands
  `WalkController` a *displacement* — not a velocity, not an acceleration. The controller
  derives no horizontal motion of its own while a planner is attached, so no axis can be
  integrated twice. With no planner attached the controller falls back to the pre-14.5 input
  path; one of the two runs, never both.
* **Vertical motion belongs to the controller**: gravity, ground snap, step support, and the
  slope rule. The bridge may inject one takeoff impulse and may declare a step submerged; it
  cannot integrate height.
* **The loop closes through the controller.** The resolved feet position, vertical velocity,
  and grounded flag are handed back to the bridge on the next step and become graph
  variables.

The horizontal source is the graph's own root travel when the data carries any, and the
resolved gait speed otherwise. Vanilla data always takes the second branch, and that is a
measurement rather than an assumption: **not one of the 2,654 HKX files under
`meshes\actors\character\` contains an `hkaAnimatedReferenceFrame`, and every
`hkaSplineCompressedAnimation` in the locomotion clips leaves `m_extractedMotion` null.**
Skyrim's locomotion clips animate in place and the engine supplies the travel; the graph is a
consumer of `Speed` and `Direction`, not the source of movement. Driving `mt_behavior.hkx`
for three seconds of walking accumulates 0.04 units of root-bone travel in total — jitter,
not locomotion. The root-motion branch stays because a data set that does carry extracted
motion must drive the capsule from it rather than be silently ignored; the threshold between
the two is 10 units per second, an order of magnitude above the measured jitter and two
orders below the walk gait.

A paused frame (`dt == 0`, menu mode — see [menu mode](/engine/menu-mode.md)) is a total
no-op: no variable write, no event, no graph update, no jump latch consumed, no capsule
movement.

## Gaits

Sneak outranks sprint, which outranks run, and swimming replaces all three. Crouching cancels
a sprint rather than stacking with it. The resolved gait picks the speed the displacement is
built from and the value written into the graph's `Speed` variable.

## Jump

The jump key latches one request until a fixed step consumes it. A jump needs solid ground:
in the air the request is dropped rather than queued, so a held key cannot turn into a second
jump the moment the capsule lands. Takeoff sets the controller's vertical velocity, clears
grounded and any active step support, and raises `JumpUp` into the graph. `JumpFall` is
raised when the capsule leaves the ground without jumping (walking off a ledge) and
`JumpLand` when the controller reports ground again — landing is the controller's
observation, and the graph is told the capsule arrived.

## Swim

Water height comes from the cell: `CellScene.waterHeight` resolves CELL `XCLW` over the
worldspace default exactly as the drawn plane does, and `CellSceneComposition.sampleWaterHeight(at:)`
answers per world XY by the same cell-ownership rule the terrain sampler uses. Interiors
report none, because a vanilla interior authors its water as placed geometry rather than as
the cell-wide plane `XCLW` describes.

Swimming starts once the capsule bottom is 90 units under the surface and stops once it rises
to within 70, the two thresholds differing so a capsule bobbing on the boundary cannot flip
modes every step. Both are OpenSky measurements against the capsule dimensions (128 tall, eye
at 112 — the player swims at about chest depth and wades below that); no GMST in the install
states either. While swimming there is no gravity, no ground snap, and no step support: the
capsule is driven toward the depth that puts its eye at the surface, or up and down at the
swimmer's request (jump ascends, sneak descends), all clamped to 200 units/s. A swimmer
resting on a shallow bottom still reports grounded, which is what lets it walk back out.

## Response

### Terrain response

Grounded motion rejects candidate terrain whose face normal exceeds slope limit. Allowed
terrain rises snap capsule bottom to rendered plane; gravity + snap keep descending terrain
contact. Airborne player falls until bottom crosses a ground plane, then penetration resolves
to exact sampled height with zero vertical velocity.

### Static mesh response

`CapsuleWorldCollider` queries resident per-cell BVHs with swept capsule AABBs. Each fixed
step splits displacement into submoves no longer than half capsule radius -> thin surfaces
cannot tunnel between endpoints. Narrowphase supports triangle soups, precomputed convex-hull
faces, oriented boxes, scaled spheres, and transformed capsules. Closest segment/triangle or
segment/primitive pairs emit penetration normal + depth. Up to eight deepest-contact
corrections depenetrate; untouched displacement components remain -> wall contact slides.
Steep positive normals become horizontal blockers. Walkable normals ground capsule. Downward
contacts zero falling velocity; negative-up contacts stop ascent. Solver exposes
`hasUnresolvedPenetration` for 4.5 route gate.

Grounded blocked motion gets one bounded configured step attempt. Forward vertical probe accepts
only surfaces at or below slope limit; riser faces cannot become support. Controller proves
full step-height clearance, advances horizontally above blocker, then retains tread support
until capsule center reaches it. Higher obstacles or low ceilings fail clearance -> direct
wall response wins. Same probe bridges terrain to mesh treads without treating render terrain
as a mesh duplicate.

`Renderer` owns mode + controller. `GameMetalView` latches G through `CameraInputState`;
renderer drains toggle once, resets controller from current camera when entering walk, then
queries `CellStreamer`'s resident terrain + collision composition before streaming update.
First-scene framing or successful XTEL door camera reseed resets capsule pose, vertical
velocity, grounded state, fixed-step residual, and active tread support before next physics
step. F activates the exact [interaction target](/engine/interaction.md) under the walk-mode
view ray within 192 units; fly mode neither targets nor activates.

## Scope boundary

4.4 connects terrain + [static collision world](/engine/collision-world.md) to production
walk input for exterior and interior scenes. Static geometry blocks the player; actors,
dynamic rigid bodies, and moving platforms stay out of scope. M4.5 supplies the fixed
real-data route + render/physics acceptance gate.

Item 14.5 adds jump, sneak, sprint, and surface swimming, and leaves out of scope: the
rendered player body and third-person camera (items 14.6 and 14.7), NPC locomotion (M16),
combat and weapon-drawn movement (M15), underwater diving and swim camera effects beyond
surface locomotion, and footstep audio events.

## Verification

Synthetic tests:

* `TerrainHeightFieldTests`: flat/negative cells, hidden quadrants, exact east-neighbor border,
  saddle proving triangle-plane vs bilinear result.
* `WalkControllerTests`: capsule eye offset, gravity/ground snap, pitch-independent motion,
  injected walk/run speeds, slope rejection, 100 ms clamp, fixed-step partition determinism,
  no-ground fall, four resident fields traversed without lost contact.
* `WalkControllerConfigurationTests`: changing only injected step height changes whether the
  same synthetic obstacle is accepted.
* `CapsuleCollisionTests`: wall slide, ceiling, walkable ramp, low/high steps, forward tread
  probe, player-solid filtering boundary, terrain-to-mesh seam, no unresolved penetration.
* `RendererSceneSwapTests`: XTEL-style camera reseed clears grounded/controller state and
  treats actor-origin XTEL position as capsule feet before next physics step.
* `CellSceneTerrainTests`: LAND, XCLC hidden quadrant, DNAM fallback, no-terrain builder paths
  retain collision data matching rendered terrain.
* `CameraInputStateTests`: G request drains exactly once; the jump latch drains once; sprint
  follows the held key; the sneak toggle survives capture loss while sprint and jump do not.
* `LocomotionBridgeTests`: gait separation, the paused-frame no-op, census-name writes and
  reported misses, one `moveStart` per transition, the sneak toggle pair, vanilla-shaped root
  motion staying below the authority threshold, the grounded -> airborne -> land arc, a
  second jump needing the ground back, swim enter and exit across the hysteresis band, and
  two seconds of walking into a wall never integrating past it.
* `MovementTypeRecordTests`: MOVT decode, truncated SPED dropped whole, load-order override,
  and the gait speeds and jump takeoff resolving with their sources.

Env-gated real-data drive (`make realtest
T='LocomotionBridgeRealDataTests/drivesTheVanillaGraphThroughACell()'`): the vanilla
`0_master.hkx` graph bound to the bridge, driven over the launch cell's own LAND terrain with
no Metal device. Observed 2026-08-03: walk 100.08 units in one second against a resolved
100.0 gait, sprint 499.92 against 500.0, sneak 47.11 against 47.2, a jump apex 74.1 units
above the floor against the 76 units `fJumpHeightMin` states, and all ten census variables
plus all nine raised events resolving in the graph with zero misses. Trace in gitignored
`logs/locomotion-drive.log`.

Real-install scratch CLI probe decoded LAND for Tamriel `(6,-2)` through `(9,-2)`, retained
four production `TerrainHeightField` values in `CellSceneComposition`, then drove production
`WalkController` east along world Y `-8128`. Three cell borders crossed in 342 100-ms input
frames; every physics step stayed grounded, max capsule-bottom distance from sampled rendered
plane = `0.0` units. Probe code + test-host attempts removed; no game data copied or committed.

## Milestone acceptance route

`openskycli bench --walk-path` owns M4's repeatable production gate. Fixed 1/30 s input
frames feed 1/120 s controller substeps from Tamriel cell `(6,-2)` across streamed terrain to
Chillfurrow Farm `(7,-3)`. Fixed waypoints skirt decoded Whiterun wall/farm placements;
bounded deterministic sidesteps recover when a small static blocks progress. The driver then:

1. Requires grounded travel + no unresolved penetration/fall-through at every active frame.
2. Measures at least 16 units of exterior stair gain before activating door `0001633D`.
3. Requires interior CELL `00016204`, crosses at least 80% of a 192-unit floor segment, then
   returns to paired door `000163A8`.
4. Requires exterior cell `(7,-3)` + recorded return pose, zero failed cell/door builds,
   bounded phase/whole-route frames.
5. Gates active-physics wall time with a build-aware policy. Average stays <= 33.33 ms in
   every build, which preserves the sustained 30 fps requirement. Release p95 also stays
   <= 33.33 ms. Debug p95 may use two frame intervals (<= 66.67 ms) because the synchronous
   offscreen loop includes debug-runtime and scheduler variance that is absent from the
   shipping build. A user-supplied `--budget-ms` is strict for both average and p95.

The split budget keeps the performance claim on average and Release tails without making the
Debug probe flaky when an occasional frame occupies a second interval. A Debug run still
fails if sustained work exceeds one interval or at least 5% of frames exceed two intervals.
`physicsRender` contains only active-frame timing arrays; it carries no `windowSummaries`
because the `FrameStats` strings summarize fixed 120-frame windows across the unfiltered run.

Read-only real-install acceptance at 640x360: 1,065 active physics frames, avg 15.90 ms
(62.9 fps), p95 29.69 ms, max 58.28 ms; exterior stair gain 22.82 units; interior crossing
160.34 units; paired return feet `(31233.67, -9784.47, -4059.53)`. No clip, fall-through,
unresolved penetration, destination mismatch, or build error.

## Movement-tuning acceptance surface

Milestone: M4 movement tuning (issue #63)
Sidebar path: World > World > Camera
Destination id: Destination-world
Controls exercised: CameraMovementModeControl
Readout: CameraStatsLabel
Deterministic tests: WorldPanelTests, WalkControllerTests,
WalkControllerConfigurationTests, GameSettingStoreTests
Local A/B (optional, never committed): none

`CameraStatsLabel` displays walk and run values in units per second, step height in world
units, and the winning plugin or fallback source. The selector enters the controller path
that consumes the displayed immutable configuration.
