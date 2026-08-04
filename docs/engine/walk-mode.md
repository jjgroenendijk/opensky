---
type: Subsystem
title: Terrain walk mode
description: Fixed-step player capsule over streamed terrain and static mesh collision with
  gravity, collide-and-slide, slope limits, bounded step response, the movement-authority
  split that lets a behavior graph drive it, and the third-person camera and rendered player
  body that make it visible.
tags: [engine, world, terrain, collision, movement, streaming, locomotion, camera,
  milestone-14]
timestamp: 2026-08-04T00:00:00Z
---

# Terrain walk mode

Milestone 4.1 adds physical ground before mesh collision. Fly mode remains default dev
camera; G toggles walk mode. Walk mode owns capsule position + gravity while keeping existing
mouse-look and WASD/Shift input. Q/E vertical input applies only in fly mode.

Milestone 14 item 14.5 adds the other half: sprint, sneak, jump, and swim, and the rule that
decides who moves the capsule once a
[behavior graph](/engine/behavior-runtime.md) is attached to it. Item 14.6 makes it visible:
a third camera mode that watches the player from behind, and a rendered body driven by that
graph.

## Contents

* [Terrain collision surface](#terrain-collision-surface)
* [Controller](#controller)
* [Input](#input)
* [Movement authority](#movement-authority)
* [Gaits](#gaits)
* [Jump](#jump)
* [Swim](#swim)
* [Camera modes](#camera-modes)
* [Third-person camera](#third-person-camera)
* [The player body](#the-player-body)
* [Response](#response)
* [Scope boundary](#scope-boundary)
* [Verification](#verification)
* [Milestone acceptance route](#milestone-acceptance-route)
* [First-person acceptance surface](#first-person-acceptance-surface)
* [Third-person acceptance surface](#third-person-acceptance-surface)
* [Movement-tuning acceptance surface](#movement-tuning-acceptance-surface)

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
| G | Cycle camera mode: fly -> first person -> third person | OpenSky dev control; vanilla uses F for first/third |
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

## Camera modes

`CameraMovementMode` has three cases and `G` cycles them: `fly`, `walk` (first person), and
`thirdPerson`. The `World > Camera` selector lists the same three in the same order, so
neither the key nor the panel can reach a mode the other cannot, which is what keeps the key
an accelerator rather than the only way in (`docs/tools/app-ui.md`).

`walk` and `thirdPerson` are the same simulated player: one capsule, one `LocomotionBridge`,
one behavior graph. Only where the eye ends up differs. Everything gated on "the player
exists" — the interaction ray, the trigger-volume capsule, the locomotion readout — tests
`isPlayerControlled` rather than comparing against `.walk`, so a third-person session keeps
all of it.

Switching between the two player modes does not move the capsule. Only entering from fly
re-seats it under the current eye; re-seating on every camera keypress would teleport the
player by the orbit distance each time.

## Third-person camera

`ThirdPersonCamera` is pure math over the capsule pose and the look angles the shared
`FreeFlyCamera` already owns. It integrates nothing, so switching modes changes where the eye
is and nothing about where the player is looking.

Every distance is derived from something OpenSky can measure, because the numbers vanilla's
own camera uses are not in the data. That is a probe result, not an assumption: `Skyrim.esm`
declares no `fOverShoulder*`, `fVanityMode*`, or `fMouseWheelZoom*` game setting, and the
install's shipped `Skyrim_Default.ini` carries no `[Camera]` section at all. Those values
live in the retail executable and in a user's own `My Games` profile, neither of which
OpenSky reads. So the framing comes from the player capsule and the vertical field of view
the renderer projects with:

| Quantity | Value | Where it comes from |
| --- | --- | --- |
| Pivot height | 112 units | The capsule's own eye height — the point first person looks from |
| Fill fraction | 0.6 | Chosen, not measured: the one taste decision, made once |
| Orbit distance | ~167 units | `(height / 2 / fill) / tan(fov / 2)` at a 128-unit capsule and a 65-degree vertical fov |
| Shoulder offset | 24 units | One capsule radius: the shoulder line of the measured capsule |
| Collision radius | 8 units | A third of the capsule radius: thin enough to follow into a doorway, wide enough to clear the 10-unit near plane |
| Minimum distance | 24 units | The shoulder offset, so a fully squeezed camera still sits outside the capsule silhouette |

Sharing the pivot with first person is what makes the two modes agree about what is at the
centre of the screen. The orbit is a sphere rather than a ring: pitch raises the eye and
shortens its horizontal reach, at a constant radius.

Collision-aware zoom goes through the same `CapsuleWorldCollider` seam the character
controller collides with, so the camera sees exactly the shapes the player does and no second
collision world exists to disagree with the first. A small probe capsule is swept from the
pivot along the offset line; the answer is read back as a *distance* and re-applied to the
original direction, because collide-and-slide can push the probe sideways and the camera only
ever moves along its own line. A teleport resets the zoom, so the readout never reports the
squeeze of the place the player just left.

## The player body

The player resolves through `ActorTemplateResolver` and `ActorVisualResolver` exactly as a
streamed ACHR does, so slot masking, FaceGen, and the M12 equipment attachment path apply to
it without a second implementation. Two things differ, and only two: the base record is named
directly — `Skyrim.esm` `NPC_ 00000007`, editor ID `Player`, which `openskycli actor --npc
00000007` resolves to a skeleton, an iron outfit, and a FaceGen head — because the player has
no ACHR to read it from, and the transform comes from the character controller rather than
from a record.

The body is streaming-independent. `Renderer.setScene` replaces every cell-owned draw list
several times a minute and the player is not owned by a cell; it is the thing the cells move
around. So the body is held by the renderer directly, its draw groups are appended to the
scene's at encode time for both the scene pass and the shadow pass, and its GPU allocations
join the residency set once and stay.

It moves every frame, and skinned geometry is placed twice: once by the draw's model matrix
and once by the bone palette. The palette is pose-in-rig-space, so the world placement rides
the model matrix, which means the draw groups are rebuilt when the transform changes rather
than baked once. That rebuild is group accumulation over the handful of meshes one actor
carries — no allocation, no upload — and it runs through `RenderScene(instances:)` so the
player is grouped by exactly the rule every other placement is grouped by. A standing player
costs one matrix comparison per frame.

The world transform is `translation(feet) * rotationZ(yaw - pi/2)`. The quarter turn is the
actor convention rather than a fudge: a Skyrim ACHR's `angleZ` is measured clockwise from
north and `MatrixMath.placement` applies it as `rotationZ(-angleZ)`, so an actor placed at
`angleZ` 0 stands unrotated and faces +Y — the character meshes are authored facing +Y —
while walk-mode yaw is measured counterclockwise from +X.

First person deliberately does not draw the body: the eye is inside its head. It draws the
`_1stperson` arms instead, on a second rig anchored to the eye and driven by a second graph
instance — the visibility matrix, the depth policy, the shadow policy, and the first-person
field of view are all in [behavior graph runtime](/engine/behavior-runtime.md), "First
person". Fly mode draws the body, so a developer can fly around the character and look at it.
The body keeps casting its shadow in every player mode, first person included.

The pose comes from the behavior graph through `PlayerAnimationPlayback`; the clock split and
the open skinning defect are in [Actor idle animation](/engine/actor-animation.md).

The player's graph is the vanilla `0_master.hkx`, loaded by `PlayerBehaviorGraph` with the
character rig from `skeleton.hkx` and an on-demand clip source over the archived animation
folder. It is attached to the already-running `LocomotionBridge` once the scene provider
exists; a bridge with no graph stays a supported configuration and queues nothing, so there
is nothing to replay at attach. The body is reassembled when the player's equipped set
changes, whichever of the panel, a container menu, or a Papyrus script changed it — the
wiring watches the resulting set rather than any one call site.

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
* `ThirdPersonCameraTests`: the three-mode cycle and which modes simulate a player, the
  orbit distance recomputed from the capsule and the fov, the framing fov matching the
  projection fov, the pivot equalling the first-person eye, the offset sitting behind and off
  the shoulder, pitch orbiting at constant radius, open space leaving the camera at the orbit
  distance, a wall behind the player pulling it in along its own line without passing
  through, the minimum distance holding against a wall pressed to the player's back, and
  reset restoring the orbit.
* `PlayerBodyAnimationTests`: dense local poses composing through the parent chain, a short
  pose keeping the reference for the rest, the conformer writing the composed matrices into
  the palette, the simulation clock rather than the wall clock driving it, the bind-pose
  reset being reversible, the bridge publishing a pose every step and dropping it on reset,
  a bridge with no graph publishing nothing, and the body facing the camera yaw and standing
  on the capsule feet across a full turn.

Env-gated player drive (`make realtest
T='PlayerBodyRealDataTests/drivesEveryLocomotionStateWithABody()'`): the vanilla graph, the
vanilla player body, and a scripted route through idle, walk, run, sprint, sneak, jump, land,
and swim over the launch cell's real terrain, asserting each gait resolves, each poses bones,
and jump, land, and swim raise their events. The launch cell is dry land, so the swim leg
runs against an injected water surface and the trace says so. Observed 2026-08-04: 22 clips
loaded with zero misses, `mt_behavior.hkx` resolved through the behavior reference, and the
state path reaching `MT_Locomotion_State`, `Sprint_State`, `MT_Sneak_Locomotion_State`, and
`MTIdleTurnState`. Trace in gitignored `logs/player-locomotion-drive.log`.

Env-gated render (`make realtest
T='PlayerBodyRenderRealDataTests/drawsTheBodyInThirdPersonOnly()'`): the body drawn in the
real launch cell from the resolved third-person camera. It asserts that the body draws in
third person, that it does not draw in first person against the identical camera pose, that a
locomotion state change moves pixels, and the M12/M13 cross-check that a reassembled body at
the same pose is byte-identical. Observed 2026-08-04: 80,693 changed pixels against a
no-body frame, 97,997 across a state change, and 0 across reassembly. Captures in gitignored
`logs/`.

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

## First-person acceptance surface

`World > First person` (`Destination-world`, `PanelSection-first-person`) carries the arms
toggle `FirstPersonArmsEnabledControl`, the field-of-view slider `FirstPersonFOVControl`, and
the readout `FirstPersonStatsLabel`. The readout is the part a frame cannot supply: whether
the `_1stperson` graph loaded and how many updates it has run, how many arm meshes survived
the MOD4/MOD5 projection, how many pieces were dropped for declaring none, whether the rig
has a camera bone and at what height, the active field of view, and any variable or event
name the first-person graph does not declare. Covered by `FirstPersonPanelTests` and
`DestinationRegistryTests`.

## Third-person acceptance surface

Milestone: M14 player locomotion, item 14.6 (issue #189)
Sidebar path: World > World > Camera
Destination id: Destination-world
Controls exercised: CameraMovementModeControl
Readout: CameraStatsLabel
Deterministic tests: ThirdPersonCameraTests, PlayerBodyAnimationTests, WorldPanelTests,
M8AcceptanceTests, CameraInputStateTests, BehaviorClipTests
Local A/B (optional, never committed): `logs/player-body-third-person.png` and
`logs/player-body-bind-pose.png` from
`make realtest T='PlayerBodyRenderRealDataTests/drawsTheBodyInThirdPersonOnly()'`

The selector now offers Fly, Walk (first person), and Walk (third person), and
`CameraStatsLabel` names the live mode so a bug report carries the camera that produced the
frame. `G` cycles the same three.

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
