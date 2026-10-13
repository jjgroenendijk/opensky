---
type: Subsystem
title: Menu scene
description: The renderer layer that draws a menu's own 3D effect meshes, such as the perk
  sky, with their own camera in place of the world.
tags: [rendering, menus, effects, nif]
---

# Menu scene

Some menus draw a 3D scene of their own instead of the world. The skills menu's
[perk sky](/engine/perk-sky.md) is the first one. The menu scene is the renderer layer
for it: a list of unlit effect meshes, each with a transform and a material, and one camera.

## How a frame draws it

1. The menu hides the world with an empty loading cover (`setLoadingCover([])`). The world
   layers are then skipped, as during a load.
2. Each frame the menu hands the renderer a `MenuScene`: eye, target, up, vertical field
   of view, and the draws in order.
3. The scene pass draws the menu scene after the world's particles and before the
   first-person arms, with the SWF layer on top.

The menu scene has no depth test and writes no depth. Draw order alone decides what
covers what. This matches the perk dome, whose shapes sit under a `BSOrderedNode`: that node
tells the game to draw its children in their stored order. The stars and lines are drawn
after the dome, so they always show in front of it.

## Materials

Every shape uses a `BSEffectShaderProperty`. The menu-scene shader uses the same effect
terms as the world's effect meshes: the emissive colour and multiple, the greyscale palette,
the falloff by view angle, and the vertex colours. The term code lives in one Metal header
that both shaders include, so the two cannot drift apart.

Blending comes from the shape's `NiAlphaProperty`, with one pipeline per blend mode, as
for particles. A shape with alpha testing on compares against its threshold in the
fragment shader.

A sequence may change a shape's material while it plays: the emissive colour, alpha, and
UV offset and scale ([sequence variables](/formats/nif-sequences.md#which-value-a-track-drives)).
The pose is computed on the CPU each frame, and each draw carries its own uniforms.

## Billboards

A shape under an `NiBillboardNode` turns to face the camera before it is drawn. The turn
happens at the billboard node, so the nodes below it keep their own rotation. The perk
star's quad, for example, is turned 45 degrees inside its billboard. The modes and the
+Z facing are on the [sequence page](/formats/nif-sequences.md#billboard-nodes).

## Residency

The meshes and textures of a menu scene join the renderer's residency set the first time
they are drawn. All of them leave it when the menu sets the scene to nil.
