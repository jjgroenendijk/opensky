---
type: Decision
title: First render cell — WhiterunExterior06
description: Target exterior cell for milestone 2.7/2.9 first render — probe criteria,
  candidate ranking, choice of Tamriel (6,-2) WhiterunExterior06.
tags: [decision, milestone-2, cell, rendering]
timestamp: 2026-07-17T00:00:00Z
---

# First render cell

Closes todo 2.7 open question: which exterior cell to render first.

## Decision

Target = Tamriel worldspace, grid (6,-2), editorID `WhiterunExterior06`.

## Criteria

Mission wants a recognizable textured cell fast -> smallest possible asset surface:

1. Small ref count (few draws, quick load).
2. Mostly STAT bases (only base type scene build 2.7 handles).
3. Few distinct models (few NIF/DDS paths to validate).
4. Recognizable content.

## Probe (2026-07-17, throwaway per AGENTS.md — not committed)

Scanned Tamriel exterior cells grid x in [-2,10], y in [-9,3] (Whiterun plains box) via
repo parsers: 170 cells, STAT index 9 720 records. Ranked by STAT ratio + model economy.

Top candidates:

| cell | grid | refs | STAT | models | scaled | non-STAT |
| --- | --- | --- | --- | --- | --- | --- |
| WhiterunExterior06 | (6,-2) | 16 | 15 (94%) | 8 | 2 | ACTI 1 |
| WhiterunExterior03 | (6,-3) | 17 | 13 (76%) | 10 | 1 | MSTT 3 |
| WhiterunExterior12 | (7,0) | 24 | 19 (79%) | 15 | 10 | TREE 5 |
| WhiterunExterior10 | (7,-1) | 34 | 28 (82%) | 17 | 10 | TREE 4, ACTI 1, FURN 1 |

Farm cells (todo's candidate area) all fail the size criterion: ChillfurrowFarmExterior
127 refs / 30 models, PelagiaFarmExterior 127 / 28, BattleBornFarmExterior 153 / 34;
ChillfurrowFarmEdge (38 refs) is 47% STAT, dominated by 18 TREE refs. Farm cell =
stretch goal after 2.7, not first target.

WhiterunExterior06 content: Whiterun city-wall segments (`wrwallcap01`,
`wrwallstr01`, `wrwallstrup128`, curve/divide variants), Jorrvaskr + Bannered Mare LOD
stand-ins — unmistakably Whiterun, seen from the plains. All 8 model paths resolve in
the vanilla BSAs; 2 scaled refs + wall curves exercise the full REFR transform
(translation, yaw, scale), matching the coordinates.md 2.7 visual-verification plan.

## MODL path prefix (probe finding, binds scene build)

STAT MODL values in `Skyrim.esm` carry no `meshes\` prefix
(`architecture\whiterun\wrcitywalls\wrwallcap01.nif`); BSA/VFS keys do. Verified on all
8 target-cell models: raw path 0/8 hits, `meshes\` + path 8/8. Scene build / MeshLibrary
must prepend `meshes\` before VFS lookup (mirror of the `textures/` rule in
[NIF mesh](/formats/nif.md)).
