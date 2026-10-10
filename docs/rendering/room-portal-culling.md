---
type: Subsystem
title: Room and portal culling
description: How an interior's room markers and portals become a graph, how the camera's
  visible rooms are found each frame, and how both culling paths skip the hidden rooms.
tags: [rendering, culling, interior, performance]
---

# Room and portal culling

An interior is cut into rooms. Doorways between rooms are portals. A room the camera cannot
see through a chain of portals is skipped, so its statics cost no draw work. This only saves
time. The image must not change.

The record fields are on the [placed references](/formats/placed-references.md#rooms-and-portals)
page. The walk below is an OpenSky policy, not a copy of the game's method, which is not
documented.

## The graph

The interior build makes one graph from the cell's references:

- A **room** is a reference with room data (`XRMR`) and a box primitive (`XPRM` type 1).
- A **portal** is a reference with a portal box primitive (`XPRM` type 3) and an `XPOD`
  pair. Each end of the pair names a room marker. A pair with a missing end, or an end that
  is not a room in this cell, is dropped.
- Two rooms are **linked** when one lists the other in `XLRM`.

Each box is the reference's placement matrix (position, rotation, `XSCL`) applied to the
local box of half size `halfExtents`. A box with no volume is dropped. A cell without rooms
has no graph, and nothing is culled.

## Which room an instance is in

When the render scene is built, each static instance is tested against every room. If its
world box touches exactly one room, it belongs to that room. If it touches none or several,
for example a door frame inside a portal, it is always drawn.

The touch test moves the instance's box into the room's frame and boxes it again, so it can
report a touch that is not there, but never misses a real one. A false touch only means
fewer instances are culled.

Actors, rigid bodies, and anything a simulation moves get no room, because they can walk out
of it.

## The visibility walk

Each frame, before the shadow pass, the renderer finds the rooms the camera can see:

1. The start rooms are every room whose box holds the camera. If there are none, culling is
   off for this frame.
2. Each open room has a screen rectangle, first the whole screen.
3. For each portal of the room, project the 8 corners of the portal box. The part of the
   room's rectangle that the projected portal covers is the rectangle of the room behind it.
   If that part is empty, the room behind is not seen through this portal.
4. A portal that holds the camera, or that crosses the near plane, keeps the whole
   rectangle. A portal fully behind the camera is skipped.
5. A linked room opens with the same rectangle, without narrowing.
6. A room seen through several portals keeps the union of their rectangles. A room whose
   rectangle grows is walked again, so the walk ends when no rectangle grows.

The result is a bitset with one bit per room.

## Both culling paths

- The **CPU path** skips an instance whose room bit is clear, before the frustum test.
- The **GPU path** writes each instance's room into the `CullInstance` room word. The
  camera view's `CullParameters` carries the bitset's word count, and a separate buffer holds
  a counter and the bitset. The kernel skips the instance and adds one to the counter.

Rooms cull only the camera view, never a shadow cascade. A hidden room can still cast a
shadow into a room the camera sees.

## Settings and readout

The player setting `rendering.roomCulling` turns it on or off. It is on by default. The
launcher's Graphics page writes it, and so does the switch in
`Developer > Rendering Performance > Room Culling` (`RoomCullingEnabledControl`). The readout
(`RoomCullingStatsLabel`) shows the rooms, the portals, the rooms seen, and the camera
instances that rooms culled over both paths.

The room-culled count is part of the culled count that the [GPU culling](/rendering/gpu-culling.md)
readout shows.
