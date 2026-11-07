---
type: Engine
title: Head part assembly
description: How OpenSky builds an actor's head from HDPT head parts instead of the baked
  FaceGen head, and what the assembled head does not show yet.
tags: [engine, actor, facegen, app-ui]
---

# Head part assembly

The game ships one baked FaceGen head per NPC: a single mesh with the face, hair, brows,
and eyes merged. OpenSky draws that head by default. It can also build the head from its
parts, the `HDPT` records ([Head parts](/formats/head-parts.md)). This is the path a
custom character will need, because a custom character has no baked head.

The choice lives in the actor's presentation state for the session, and a change rebuilds the
actor's cell.

## Which parts

Only a race with the FaceGen head flag gets assembled parts.

1. Start from the race defaults: `RACE` male or female head parts.
2. Each `NPC_` head part (`PNAM`) replaces the default of the same part type. A part of
   type misc is added and replaces nothing.
3. Each part expands into its extra parts (`HNAM`), depth first. A part enters the head
   once, so a loop of extra parts stops.
4. A part whose `RNAM` race list does not hold the actor's race is dropped.

Each drop is a miss with a reason: no such head part, not allowed for the race, no model, or extra
parts loop.

## Textures and color

- The part's texture set (`TNAM` `TXST`) replaces the diffuse and normal maps of the mesh.
- Hair, facial hair, and eyebrows take the actor's hair color (`NPC_` `HCLF`). Other
  parts take their own `CNAM` color. The color multiplies the vertex colors, because the
  shader multiplies by them. A mesh without vertex colors gets the color as its vertex
  color.

## Shape, colour, and expressions

An assembled head, on an NPC or on the player, gets the same face data the race menu edits:

- Each head part's TRI files share one morph buffer per skinned mesh. The `HDPT` `NAM0` kind
  says what each file is: 0 race, 1 expression, 2 chargen. A file whose vertex count differs
  from the mesh is left out.
- The race TRI has one target per race, named after the race, such as `NordRace`. The head
  shows the target of the race's morph race (`RACE` `NAM8`), else its own, at weight 1.
- The chargen TRI takes the `NAM9` sliders and the `NAMA` parts, as on the
  [race menu](/engine/race-menu.md#the-drawn-head) page.
- The race and chargen weights never change. The expression TRI's targets move with blinks,
  expressions, and lip sync ([face morphs](/engine/face-morphs.md)).
- The face part paints the `TINI` tint layers into a face tint, at each layer's `TINC` colour
  and `TINV` percent. `FTST` picks the complexion texture set.

[WARNING] The race target at weight 1 is OpenSky's reading of the data, not observed in the
game ([unverified values](/engine/unverified-values.md)).

On the install, Heimskr's assembled head covers the same pixels as his baked head with an
intersection-over-union above 0.85.
