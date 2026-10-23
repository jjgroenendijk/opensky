---
type: Tool
title: Preview render
description: How `openskycli preview` renders one record, reference,
  mesh, or cell from fixed angles, and what the report holds.
tags: [tool, cli, rendering, preview]
---

# Preview render

A preview renders one thing from fixed camera angles and measures each image. An agent uses it
to look at an asset, an NPC, or a cell without starting the game and walking there. The pipeline
lives in the `OpenSkyPreview` module.

## Targets

| Target | Option | What is drawn |
| --- | --- | --- |
| Base record | `--record <FormID or EDID>` | `NPC_` with its outfit, `STAT`, `MSTT`, `FURN`, `DOOR`, `CONT`, `ACTI`, `ARMO` (the world model), `WEAP`, `MISC`, `FLOR`, `TREE`, or `LIGH` with its light |
| Placed reference | `--ref <FormID>` | The reference with its own scale and base |
| Mesh | `--mesh <archive path>` | One `.nif`, with its own textures |
| Cell | `--cell <EDID>`, or `--worldspace <EDID> --x <n> --y <n>` | The whole cell |

A cell option next to a record or mesh names the cell it stands in. Every record comes from the
whole active load order, so a record a plugin overrides shows the winning version.

## Stages

- `studio`, the default for a record, reference, or mesh: a grey background, one fixed light, no
  fog, and no sun shadows. Only the target is in the scene.
- `cell`, the default for a cell: the cell's own lighting template, weather, and sky, at
  `--time-of-day` (default 13) and with `--weather` if given. An exterior also draws distant LOD.

A record or mesh on the cell stage stands at the reference that `--focus` names. Without
`--focus` it stands in the middle of the cell, on the floor found by a ray down through the
cell's collision. A reference on the cell stage is drawn where it is placed.

## Camera

The camera fits the target's bounds and looks at their centre. An NPC is framed by a box around
its feet up to its head, not by its skinned mesh bounds, which are much larger than the body.

| Angle | Yaw | Pitch |
| --- | --- | --- |
| `front` | 0 | 10 |
| `side` | 90 | 10 |
| `back` | 180 | 10 |
| `top` | 0 | 89 |
| `three-quarter` (default) | 45 | 20 |

Yaw 0 puts the eye on the +Y side, which is the side a Skyrim model faces. `--angles all` writes
all five. `--yaw` and `--pitch` give one `custom` view instead, and `--distance` sets the eye
distance of every view; a distance under 64 units is raised to 64.

A cell target uses the bounds of the `--focus` reference. An interior with no focus uses the
arrival point of the first door that leads into it, at eye height, so the view starts where a
player enters. An exterior with no focus frames the whole cell.

## Output

The CLI writes into `.logs/preview/<UTC>/` unless `--out` names a folder. Each view writes
`<view>.png` and `<view>.json`, and `report.json` lists them all. A view report holds:

- the view: name, yaw, pitch, and distance;
- what drew: draw calls, drawn instances, triangles, and the coverage;
- the framing bounds;
- the resolved target: kind, record type, EDID, FormID, plugin, mesh path, and cell;
- the stage, time of day, and weather;
- unresolved assets: a mesh that failed to load, a missing texture, or an animation that did
  not bind.

Coverage is the share of pixels that differ from the most common colour by more than 8 in some
channel. The most common colour is the background, so coverage 0 means nothing visible was
drawn. A view with no drawn instance or with coverage 0 is blank, and the command exits 1.

The images show game assets, so they stay in `.logs/` and never go into a commit
([run output](/tools/run-output.md)).

## The same input gives the same image

The render does not depend on the clock. The animation time is 0, the weather is fixed by the
request, and the camera comes only from the angles and the bounds. Two runs of the same command
give byte-identical PNGs.
