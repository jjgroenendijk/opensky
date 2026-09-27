---
type: Convention
title: Sidebar acceptance record
description: The record every milestone acceptance writes into its closing PR - sidebar path,
  destination and control accessibility ids, readout, and the tests that are the evidence.
tags: [app-ui, verification, acceptance, convention]
---

# Sidebar acceptance record

Every milestone ships a surface in the main-app sidebar (`AGENTS.md`, "Main-app verification
surface"). When the milestone is accepted, the closing PR or issue carries one record that
says how a user reaches that surface. The record does not go in `docs/`. How to build the
surface is in [Main-app UI framework](/tools/app-ui.md).

## Evidence

The record is mandatory. A screenshot is not.

The deterministic tests are the evidence. These are the panel tests that check geometry and
accessibility ids, the destination checks in `DestinationRegistryTests`, and any offscreen
render test the milestone already has. If they pass, the gate passes.

An A/B capture (one frame before the change, one after) can still help a human reviewer.
It is optional, it goes in `logs/`, and it is never committed. A frame rendered from a real
install contains Bethesda textures, meshes, and UI art, so committing it would share game
content (`AGENTS.md`, "Legal & IP boundary").

## Format

```text
Milestone: M8.4.3
Sidebar path: World > HUD & Interaction > Elements
Destination id: Destination-hudInteraction
Controls exercised: HUDLayerEnabledControl, HUDCrosshairControl, HUDScaleControl
Readout: HUDElementsStatsLabel
Deterministic tests: HUDInteractionPanelTests, DestinationRegistryTests
Local A/B (optional, never committed): logs/probe/20260804T191739Z/hud-elements-ab.png
```

- **Sidebar path**: the exact path a user clicks, with section names, spelled as the sidebar
  and section headers spell it.
- **Destination id**: the accessibility id of the sidebar row. It is always
  `Destination-<id>`, where `<id>` is registered in `DestinationRegistry`.
- **Controls exercised**: the accessibility ids of the controls the acceptance used, not
  every control on the panel. Some ids are built at run time, for example
  `Audio<Category>VolumeControl` in `AudioOutputSection.swift`. Name those as a family and
  say so, because a search for the full id finds nothing.
- **Readout**: the accessibility id of the label whose text shows that the behavior
  changed. A record without a readout is incomplete, because nothing is left to check again.
- **Deterministic tests**: the test classes that check all of the above.
- **Local A/B**: a run directory under `logs/` ([run output](/tools/run-output.md)), or
  `none`. `make prune` deletes old run directories, so the tests stay the lasting evidence.
