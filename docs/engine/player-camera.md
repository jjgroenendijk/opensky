---
type: Subsystem
title: Player camera and body
description: The fly, first-person, and third-person camera modes, the third-person framing and
  where each number comes from, collision zoom, and the rendered player body.
tags: [engine, camera, player, rendering, locomotion]
---

# Player camera and body

The player capsule is on the [walk mode](/engine/walk-mode.md) page. This page covers where the eye
is, and how the player's body is drawn.

## Camera modes

There are three modes, and `G` cycles them: fly, walk (first person), and third person. The
World > World > Camera selector lists the same three in the same order, so the key and the panel
reach the same modes ([main-app UI](/tools/app-ui.md)).

First and third person are the same simulated player: one capsule, one movement bridge, and one
behavior graph. Only the eye differs. Everything that needs a player (the use-key ray, the trigger
capsule, the movement readout) asks "is the player in control?", not "is this walk mode?". So third
person keeps all of it.

Switching between the two player modes does not move the capsule. Only entering from fly places it
under the current eye. Placing it on every key press would move the player by the orbit distance
each time.

The dialogue camera is not a fourth mode. It overrides the view on top of the current mode and
gives it back ([dialogue camera](/engine/dialogue-camera.md)). Two rules read the override, not the
mode, because it moves the eye out of the player's head in any mode:

- The body is drawn and the first-person arms are hidden, so a first-person player sees their
  character in the shot, not a pair of arms in front of a camera that is no longer theirs.
- The shared world field of view is used, not the first-person one, so every conversation is framed
  alike.

## Third-person framing

The third-person camera is pure math over the capsule pose and the look angles. It integrates
nothing, so switching modes changes where the eye is, not where the player looks.

The numbers vanilla's camera uses are not in the data. `Skyrim.esm` has no `fOverShoulder*`,
`fVanityMode*`, or `fMouseWheelZoom*` setting, and the shipped `Skyrim_Default.ini` has no
`[Camera]` section. Those values are in the game executable and in the user's own `My Games`
profile, and OpenSky reads neither. So the framing comes from the capsule and the vertical field of
view:

| Quantity | Value | Source |
| --- | --- | --- |
| Pivot height | 112 units | The capsule's eye height, where first person looks from |
| Fill fraction | 0.6 | Chosen, not measured: the one taste decision, made once |
| Orbit distance | about 167 units | `(height / 2 / fill) / tan(fov / 2)` for a 128-unit capsule at a 65 degree vertical field of view |
| Shoulder offset | 24 units | One capsule radius, the shoulder line |
| Collision radius | 8 units | A third of the capsule radius: thin enough for a doorway, wide enough to clear the 10-unit near plane |
| Minimum distance | 24 units | The shoulder offset, so a squeezed camera still sits outside the capsule |

Sharing the pivot with first person means both modes agree on what is in the middle of the screen.
The orbit is a sphere: pitch raises the eye and shortens its horizontal reach at the same radius.

## Collision zoom

The camera collides through the same collider the capsule uses, so it sees exactly the shapes the
player does. A small probe capsule is swept from the pivot along the offset line. The result is read
as a distance and applied along the original direction. Collide-and-slide can push the probe
sideways, but the camera only moves along its own line. A teleport resets the zoom.

The dialogue camera uses the same probe. Two copies would sooner or later disagree about what a
wall does to an eye.

## The player body

The player resolves through the same template and appearance code as a placed `ACHR`
([actor resolution](/engine/actor-resolution.md)). So slot masking, FaceGen, and equipment work with
no second copy. Two things differ:

- The base record is named directly: `Skyrim.esm` `NPC_` `00000007`, editor ID `Player`. The player
  has no `ACHR` to read it from. `openskycli actor --npc 00000007` resolves it to a skeleton, an iron
  outfit, and a FaceGen head.
- The transform comes from the character controller, not from a record.

The meshes are assembled on the cell build queue, because the builder and its mesh and texture
caches live there ([concurrency](/decisions/concurrency.md)). An equipment or face change sends a
request with a new generation number. The frame drains the finished assembly, binds it to the
graph's skeleton and pose, and shows it. A result for an older generation is dropped, so moving a
race menu slider quickly shows only the last face.

The body does not belong to a cell. Scene changes replace every cell's draw list several times a
minute, and the player is what the cells move around. So the renderer holds the body itself, adds
its draw groups to the scene pass and the shadow pass at encode time, and adds its GPU memory to the
residency set once.

Skinned geometry is placed twice: by the draw's model matrix and by the bone palette. The palette is
the pose in skeleton space, so the world placement is the model matrix. So the draw groups are
rebuilt when the transform changes. That is grouping the few meshes of one actor, with no allocation
and no upload, by the same rule as every other placement. A standing player costs one matrix compare
per frame.

The world transform is `translation(feet) * rotationZ(yaw - pi/2)`. The quarter turn is the actor
convention. An `ACHR`'s `angleZ` is measured clockwise from north, and placement applies
`rotationZ(-angleZ)`. So an actor at `angleZ` 0 is not rotated and faces +Y, which is how character
meshes are built. Walk mode yaw is measured counterclockwise from +X.

First person does not draw the body, because the eye is inside its head. It draws the `_1stperson`
arms instead, on a second skeleton at the eye, driven by a second graph
([first person](/engine/first-person.md)). Fly mode draws the body, so a developer can fly around
the character. The body casts its shadow in every player mode, first person included.

The pose comes from the behavior graph ([actor animation](/engine/actor-animation.md)). The graph is
the vanilla `0_master.hkx`, with the character skeleton from `skeleton.hkx` and clips loaded on
demand from the animation archive. It is attached to the running movement bridge once the scene
provider exists. A bridge with no graph is a supported setup and queues nothing.

The body is rebuilt when the player's equipped set changes, whether the panel, a container menu, or
a script changed it. The wiring watches the resulting set, not any one caller.

## Controls

- World > World > Camera: the mode selector. The readout names the live mode, so a bug report
  carries the camera that made the frame. It also shows walk and run speed, step height, and where
  each value came from.
- World > First person: the arms toggle, the field of view slider, and a readout of the
  first-person graph, the arm meshes, the camera bone, and any name the first-person graph does not
  declare ([first person](/engine/first-person.md)).
