---
type: Subsystem
title: Dynamic body contacts
description: How a moving body finds contacts against convex shapes and triangle meshes, the
  three rules that make a surface's side trustworthy, and shape sweeps.
tags: [engine, physics, collision, havok]
---

# Dynamic body contacts

This page covers how the [dynamic body](/engine/dynamic-bodies.md) solver finds contacts. Every
contact comes from one sample point with a skin radius on one body, tested against the other
surface. A hull's samples are its corners, and a radial volume's are its two segment ends. The only
question asked of the other surface is: how deep is this sphere inside you?

For a convex volume, the answer is the least separated face plane of a hull, or the closest point
on the segment of a radial volume.

## Triangles need a side

Against a triangle the answer must be signed. An unsigned distance flips the push direction the
moment a corner passes through a floor, which pushes the body further through. Three rules make the
sign trustworthy. Each replaced a rule that real data proved wrong.

### A surface faces the way it is wound

A decoded triangle mesh's normal comes from its winding. Vanilla winds front faces outward. This
was checked over a whole interior's architecture and furniture.

The old rule turned the normal toward the body's center of mass. It assumed that a convex body
resting on a surface has its center outside it. Real clutter breaks that: one vanilla model's
decoded center of mass is below every corner of its own collider. It read the shelf it stood on as
facing down, was pushed through the shelf, and sped out of the world. Any body thin enough to sink
past half its thickness flips the same way.

`bhkBoxShape` and `bhkConvexVerticesShape` are the exception. Their triangle connections are made
by OpenSky, not written by an author, so their winding means nothing. They face away from an
interior point instead: the box's origin, or the hull's point cloud center. Both are exact for a
convex shape.

### The nearest surface of a shape decides

Ranking by depth picks the far face of anything a sample is inside. That pushed clutter placed just
inside a shelf top down through the shelf.

Ranking by distance is only half the fix. A near face that says "outside" must overrule a far face
that says "deep inside". Otherwise a shape acts like loose faces, not a solid. Without this, a body
hovering three units over a shelf board found the board's underside twenty units away, was told it
was twenty units inside, and was pushed down through it. So a triangle returns its distance whether
or not there is penetration, and the caller keeps the nearest answer of either kind.

### A triangle is prepared once

A step asks the same triangle about every sample of every nearby body. So each triangle stores its
cross product, normal, facing, and bounds once. A sample's query then skips a triangle with one dot
product: the distance to the triangle's plane is a lower bound on the distance to the triangle, so a
triangle that cannot beat the current best never reaches the closest-point test. This skip is exact.

Triangle work runs in the shape's own space. A placed shape has many more corners than a body has
samples. So moving a few samples through one inverse matrix is cheaper than moving every triangle
through the forward one. The placement is a rotation and translation with uniform scale, so lengths
convert back exactly.

## Two limits

- Contact margin, 1.5 units, is added to every sample's skin. A hull corner has no skin of its own.
  Without a margin, a resting box would make contacts only while already inside the floor, and
  would jitter between touching and free.
- Recovery depth, 48 units, is how far behind a surface a contact still counts. Past it, the sample
  belongs to other geometry, so a body above one floor is not pulled by a triangle in the room
  below. It is capped per body at the body's own size: a sample cannot be deeper inside a surface
  than its body is big. The depth also grows the box used to find candidate triangles. A flat 48
  units around a tankard let almost half a room's triangles through to the exact test. Scaling it
  to the body halved the step time.

## Shape sweeps

A shape sweep moves a sphere or capsule along a straight line against placed collision, and returns
the first hit. Hit volumes and projectiles use it, and it checks the tunneling guard. It reuses the
tests above: an overlap test at sampled distances along the path, then bisection onto the first
touching distance.

Growing the static shapes by the swept radius is exact for spheres and capsules, and too large for
triangles and hulls. So a sweep can report a hit a little early, never late. That is the safe side
for both users. Ties break like the use-key ray: nearest first, then the lower reference FormID.
