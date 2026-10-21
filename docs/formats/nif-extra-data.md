---
type: File Format
title: NIF extra data
description: The NiExtraData blocks of Skyrim SE meshes, their layouts, and what OpenSky
  does with each.
tags: [format, mesh]
---

# NIF extra data

An extra data block is a named value that a scene object carries. A node lists its extra
data refs in its shared `NiObjectNET` fields ([NIF](/formats/nif.md#shared-node-fields)).
The game reads the root node's extra data when it loads a model, for example the `BSX`
flags and the `INV` inventory marker.

Reference: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml),
develop commit `292bb9403cbf4052c58d66e80906b6bde1700779`. Every block below starts with the
`NiExtraData` name, a uint32 string-table index (-1 is none). The layouts were confirmed by
`openskycli gaps`: it decodes every block of every vanilla mesh with the same decoder and
reports a block whose bytes are not used up exactly.

`NiStringExtraData`, `NiTextKeyExtraData`, `BSBehaviorGraphExtraData`, and
`BSFurnitureMarkerNode` are on the [NIF](/formats/nif.md) page.

## Layouts

After the name:

| Block | Fields |
| --- | --- |
| `NiIntegerExtraData` | uint32 value |
| `BSXFlags` | uint32 flags, below |
| `NiFloatExtraData` | float32 value |
| `NiBooleanExtraData` | uint8 value |
| `NiStringsExtraData` | uint32 count, then that many `SizedString` |
| `NiBinaryExtraData` | uint32 count, then that many bytes |
| `BSInvMarker` | uint16 x 3 rotation in thousandths of a radian, float32 zoom |
| `BSBound` | float32 x 3 centre, float32 x 3 half size |
| `BSDistantObjectLargeRefExtraData` | uint8 large reference flag |
| `BSDecalPlacementVectorExtraData` | float32 value, uint16 block count, then blocks |
| `BSBoneLODExtraData` | uint32 count, then pairs of uint32 distance and string index |

A decal placement block is a uint16 vector count, then that many points (float32 x 3),
then the same number of normals (float32 x 3).

## BSX flags

`nif.xml` `BSXFlags`, by bit: 0 animated, 1 Havok, 2 ragdoll, 3 complex, 4 add-ons, 5
editor marker, 6 dynamic, 7 articulated, 8 needs transform updates, 9 external emittance,
10 magic shader particles, 11 lights, 12 breakable.

Bit 4 says the model holds add-on nodes. The condition function `CanHaveFlames` reads it
(<https://ck.uesp.net/wiki/CanHaveFlames>).

## Inventory marker

`BSInvMarker` sets how the inventory menu turns and zooms a model. `nif.xml` stores the
three angles as uint16 values. OpenSky reads them as thousandths of a radian: vanilla values
are at most 6283, which is 2 pi in thousandths. This reading is not confirmed in the game. NIF matrices
act on row vectors, so OpenSky turns a column-vector model by the negated angles: Z, then
Y, then X. The zoom multiplies the size the menu fits the model to.

OpenSky's inventory preview turns the model by the marker before it measures the model's
bounds, then fits and centres it, scales by the zoom, and spins it by the menu's yaw.

## Add-on nodes

A `BSValueNode` is an `NiNode` with a uint32 value and a uint8 flags byte (bit 0 billboard
world Z, bit 1 use player adjust). The value is the `DATA` index of an `ADDN` record. The
game loads that record's model and places it at the node
(<https://ck.uesp.net/wiki/AddOnNode>). The wiki gives examples: `CWFXCatapultProjectile.nif`
uses indices 5, 6, 71, and 74.

The cell builder places each add-on model at its node when it builds a cell. A hidden
subtree, and every child of a switch node but the active one, holds no add-on nodes. When
two `ADDN` records use the same index, the record with the lowest form ID wins. The add-on
record's sound and particle system cap are not used.

## What uses the rest

The mesh preview in the sidebar lists every decoded block with its fields. The values
below have no other consumer yet:

- `BSBound` is the bound the game uses for a skeleton or a creature.
- `BSDistantObjectLargeRefExtraData` marks a model the game may draw as a large
  reference in distant cells.
- `BSDecalPlacementVectorExtraData` lists where blood decals may go on a model.
- `BSBoneLODExtraData` gives the camera distance at which each bone stops animating.
