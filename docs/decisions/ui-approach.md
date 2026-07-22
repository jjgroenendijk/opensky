---
type: Decision
title: UI approach - native Metal, no Scaleform
description: M8 UI is native Metal screen-space rendering + AppKit dev panels; vanilla
  Scaleform SWF runtime is out of scope. System font now; SWF font extraction optional
  M18+ polish.
tags: [decision, ui, rendering, scaleform, fonts]
timestamp: 2026-07-22T00:00:00Z
---

# UI approach - native Metal, no Scaleform

Decided 2026-07-20 (M8 planning), recorded at M8.1.1 per roadmap.

## Decision

- No Flash runtime. Vanilla Skyrim SE UI is Scaleform GFx: compiled ActionScript 2 SWF
  movies (`Interface/*.swf`) driven by an embedded Flash player. Reimplementing a
  correct AS2 VM + SWF display list + GFx extensions is a full second VM project with
  weak open documentation -> out of scope for the engine mission.
- UI shell is native: screen-space 2D pass in our Metal 4 renderer for in-world UI
  (HUD, menus - M8.1+), AppKit for dev/verification panels (existing sidebar surface).
- Engine UI layer draws inside the existing scene encoder as the final draws over the
  finished 3D frame: one pipeline, glyph-atlas + white-texel quads, premultiplied
  alpha, pixel-space layout with points -> pixels scale handling. Impl:
  [screen-space UI](/rendering/ui.md).
- Fonts: system font via CoreText now. Vanilla glyph look (`fonts_en.swf`
  DefineFont2/3 extraction via public Adobe SWF spec) is optional M18+ polish
  (roadmap M18.F) and never gates gameplay.
- Strings: vanilla `Interface/Translations/*_english.txt` localized labels still load
  (M8.1.3) - text content stays authentic even though presentation is native.

## Rationale

- Correctness priority is world behavior, not Flash fidelity. Menus need text, quads,
  input focus - a native layer delivers that in days, an AS2 VM in months.
- Legal cleanliness: SWF movies are Bethesda content; running them requires shipping
  nothing, but reimplementing GFx internals invites Scaleform-SDK contamination. Native
  layer reimplements observed screen behavior only.
- Native feel ranks above completeness (AGENTS.md priorities): Metal-rendered UI
  integrates with our pass/residency/stats conventions, resolution + backing-scale
  handling stays ours.
- Precedent: SkyUI replaced vanilla menus wholesale -> menu layout is not
  load-bearing for compatibility; records/strings are.

## Consequences

- HUD/menu layouts are OpenSky designs; visual parity with vanilla is non-goal until
  M18.F fonts + polish.
- Mods shipping custom SWF menus will not render their UI; document as unsupported.
- All M8+ UI work builds on the M8.1.1 screen-space layer; AppKit stays confined to
  dev panels so gameplay UI remains portable to the render path.
