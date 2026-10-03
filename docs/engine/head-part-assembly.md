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

World > AI & Navigation > Head Assembly switches the selected actor between the two and
lists its parts. The choice lives in the actor's presentation state for the session, and a
change rebuilds the actor's cell.

## Which parts

Only a race with the FaceGen head flag gets assembled parts.

1. Start from the race defaults: `RACE` male or female head parts.
2. Each `NPC_` head part (`PNAM`) replaces the default of the same part type. A part of
   type misc is added and replaces nothing.
3. Each part expands into its extra parts (`HNAM`), depth first. A part enters the head
   once, so a loop of extra parts stops.
4. A part whose `RNAM` race list does not hold the actor's race is dropped.

Each drop is a miss with a reason: no such head part, not allowed for the race, no model,
or extra parts loop. The sidebar lists them.

## Textures and color

- The part's texture set (`TNAM` `TXST`) replaces the diffuse and normal maps of the mesh.
- Hair, facial hair, and eyebrows take the actor's hair color (`NPC_` `HCLF`). Other
  parts take their own `CNAM` color. The color multiplies the vertex colors, because the
  shader multiplies by them. A mesh without vertex colors gets the color as its vertex
  color.

## Differences from the baked head

- The face part gets no tint layers and no `FTST` face texture set. Skin color comes only
  from the texture set.
- The assembled head is static. It has no expression morphs (`.tri`), so it does not
  blink or speak.
- Race morphs and chargen sliders are not applied. The face part keeps its default shape.

On the install, Heimskr's assembled head covers the same pixels as his baked head with an
intersection-over-union above 0.85.
