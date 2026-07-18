---
type: Subsystem
title: Interior door transitions
description: Interior CELL build, DOOR/XTEL resolution, proximity activation, camera
  teleport, suspended exterior streaming, return flow.
tags: [engine, world, interior, door, streaming]
timestamp: 2026-07-19T00:00:00Z
---

# Interior door transitions

M3.6. One transition path covers exterior -> interior + interior -> exterior. Format
facts: [record decoders](/formats/records.md). Impl:
`CellSceneBuilderInteriors.swift`, `CellStreamerTransitions.swift`.

## Interior build

`buildInteriorScene(cellFormID:)` walks CELL top group, type-2 block, type-3 sub-block,
then matching CELL + following type-6 children. Expected block/sub-block labels come from
FormID object ID decimal ones/tens digits. Matching labels run first; full legal-group
fallback handles stale CK labels. CELL record identity wins. DATA 0x01 must mark interior.

Persistent type-8 + temporary type-9 children reuse exterior ref walk. STAT + shared
ModelBase index resolve objects, now including DOOR MODL. Interior `CellScene` carries no
LAND, procedural sky, exterior water plane, or distant LOD. `location = .interior(FormID)`
replaces XCLC identity. Interior lighting resolves XCLL against LTMP -> LGTM, then adds
supported direct LIGH + XEMI placements. Interior water + portals remain later work.

## Door resolution

Scene build retains each drawable DOOR REFR with XTEL as `PlacedDoor`: source FormID,
position, destination payload. Renderer receives normal DOOR model placement. Main thread
can select a door without reading plugin bytes.

Exterior teleport refs are persistent: Skyrim.esm stores them under WRLD persistent CELL
`(0,0)`, not physical grid cell. Builder caches that persistent ref set, maps each XTEL
REFR position through 4096-unit cell floor division, then merges it into physical streamed
cell. Storage cell drops out-of-grid teleport refs. Same position rule chooses exterior
destination scene on return.

Transition build runs on existing serial cache-confined runner:

1. Resolve source REFR + exact 32-byte XTEL.
2. Resolve destination REFR; require its NAME base record type DOOR.
3. Find destination interior CELL owner, or derive exterior cell from REFR position.
4. Build exact owner cell; return scene + XTEL position/rotation.

Current engine loads Skyrim.esm only -> transition FormIDs resolve within that plugin.
Load-order override support waits for multi-plugin world loading.

## Activation + streaming

`F` latches one activation request. Each frame streamer picks nearest teleport door within
192 world units; requests outside radius do nothing. Raycast/interaction prompt remain
later work. Same proximity path works inside for return door.

While transition builds, current scene stays live. On interior arrival renderer swaps to
one interior scene; camera eye becomes XTEL position, pitch = rotation X, yaw = rotation Z
(roll ignored by free-fly pose). Exterior resident grid stays retained but grid diffs,
cell builds, LOD builds, unloads stop. Return arrival replaces/seeds exact exterior
destination cell, resumes grid streaming around new camera position, then normal 5x5
settlement evicts old cells/assets.

## Verification

Synthetic tests cover wrong interior labels, type-2/type-3 traversal, no terrain/sky,
DOOR draw + XTEL metadata, exact 32-byte XTEL rejection, two-way destination-cell
resolution including persistent `(0,0)` storage, proximity activation, suspended exterior
requests, exact camera pose, return
resume. `openskycli interior --out logs/interior-probe.png` selects nearest persistent
door within configured cell radius, requires exterior -> interior -> same exterior door
round trip, renders
interior arrival pose. `make probe` runs it when local install exists.

Real probe updated 2026-07-19: Chillfurrow Farm source door 0001633D at physical cell
`(7,-3)` -> destination 000163A8, interior CELL 00016204; 232 refs, 118 static draws, 69
models, 49 textures, 4 supported point lights. Reverse XTEL returned to 0001633D +
exterior `(7,-3)`, not persistent storage cell `(0,0)`. 1280x720 lit/unlit frames from exact
arrival pose show cell ambient/fog change; exterior return retains procedural sun/sky path.
