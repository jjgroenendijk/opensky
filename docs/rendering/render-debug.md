---
type: Subsystem
title: Render debug views and layer isolation
description: Debug channels gated by a function constant, a layer mask honored by the scene and
  shadow passes, how the mask combines with the subsystem switches, and why neither setting is
  saved or reaches an offscreen frame.
tags: [rendering, metal, debugging, engine, app-ui]
---

# Render debug views and layer isolation

Finding a visual bug needs a way to cut the problem in half. Two tools do that: change the scene
pass's output channel, and turn layers off one at a time. Both are in the Render Debug section of
`World > World`.

## Debug channels

A function constant gates the debug code, and a frame uniform picks the channel. Every shipping
pipeline defines the constant as false, and the five debug pipelines as true. So in a shipping
pipeline the whole debug block folds away at compile time. Changing the channel builds no new
pipeline.

Every pipeline built from a fragment that reads the constant must define it, including the shipping
grass, terrain, and water pipelines. Metal aborts pipeline validation when a referenced function
constant is undefined. The first attempt left it undefined, and every renderer start died inside
`validateWithDevice`. So one function builds all these constant values, and a new fragment cannot get
the constant without its definition.

| Mode | What it shows |
| --- | --- |
| Off | Normal shading. No debug pipeline is bound |
| Wireframe | A flat wire color, with the encoder's fill mode set to lines |
| World normals | The world normal moved from -1..1 to 0..1 as RGB |
| Texture coordinates | `fract(uv)` in red and green |
| Mip level | `calculate_unclamped_lod` on a ramp from fine and cool to coarse and warm |
| Shadow cascade | One color per sun shadow cascade, grey past the last |
| Layer category | One color per layer |

Five debug pipelines cover every mode: static mesh, skinned, terrain, grass, and water. No separate
cutout variant is needed: an alpha threshold of zero discards nothing, so the alpha-test variant
also serves opaque groups. The water debug pipeline has no blending, because a debug channel answers
"what is here", and blending it with the terrain below would hide the water in exactly the modes
meant to find it. The shadow cascade mode uses the same cascade function as shading, so it shows the
cascade shading really used.

Two modes are left out on purpose. A LOD level mode would only show near or far, because there is no
per-mesh LOD here (`NiLODNode` and `NiSwitchNode` are not traversed), and the layer mode already
separates distant LOD. An overdraw mode needs a blending pipeline set and an always-pass depth state,
and a stencil version would clash with the SWF layer's counting stencil in the same encoder.

Wireframe is a raster state, not a channel. The scene pass sets it once. Particles force fill mode
and put the old value back, because a wireframe billboard is noise. The pass goes back to fill
before the world overlay, the SWF layer, and the UI overlay, which share the encoder and would
otherwise draw a wireframe HUD.

## Layer isolation

The layers are statics, actors, distant LOD, terrain, water, sky, grass, and particles. The Swift
option set and the shader's bits use the same values.

The render scene already splits terrain, water, sky, grass, and particles, so those are filtered
where they are drawn. Statics, actors, and distant LOD share the opaque and alpha-test lists, so
they need a tag. The tag is on the placement and the instance, not on the mesh. Meshes are cached by
path and shared, so the same tree mesh is a static in one cell and a distant LOD model in the block
above it. The default is statics, so ordinary code does not change. Only actor assembly and the two
distant LOD builders set another layer. The layer is part of the group key, so a group never mixes
layers.

The shadow pass uses the same mask. Hiding statics while their shadows still fell on the terrain
would make the tool mislead.

Solo is derived, not stored: a layer is soloed when the mask has exactly one bit. Two stores for one
state can disagree. A derived value cannot.

## Combining with the subsystem switches

The renderer already has switches such as grass, particles, and precipitation. A second set of layer
switches would be two controls for the same pixels. The rule:

> A subsystem switch is the feature switch: it has meaning, it is saved, and its panel section owns
> it. The layer mask is a view filter: it is temporary, never saved, and for developers only. What
> is visible is the AND of both.

Grass drops when grass is off. Particles drop only when both particle sources are off, because cell
particles and precipitation share one layer and one draw path. Each source still checks its own
switch where it draws. The combined mask is worked out once per frame, with no GPU work.

## Not saved, and not in an offscreen frame

Unlike shadow quality, neither the channel nor the mask survives a relaunch. A session that starts
in wireframe, or with no terrain, looks like a rendering bug, and telling those apart is the point of
the tools.

For the same reason, an offscreen frame uses the normal settings unless it asks for the debug state.
Offscreen captures and bench runs stay clean whatever the sidebar says. Device tests opt in. A
window screenshot is a copy of the presented frame, so it shows the debug view.

## Where to see it

`World > World` has a Render Debug section: a channel picker, one checkbox per layer, and a solo
control that writes the same mask. A channel other than off, or a mask other than all layers, shows
the World destination's override dot, and Reset all clears both.
