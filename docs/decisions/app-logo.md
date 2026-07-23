---
type: Decision
title: App logo + icon pipeline
description: Original "North Peak" SVG mark as app identity; rsvg-convert renders AppIcon set.
tags: [branding, icon, tooling]
timestamp: 2026-07-23T00:00:00Z
---

# App logo + icon pipeline

## Decision

OpenSky mark: "North Peak" — twin angular peaks over a horizon line, frost-blue
diamond north star, bone-white strokes on black rounded tile. Owner-picked from
four original candidates (North Peak, Dragon Eye, Sky Seal, Barrow Gate).

## Legal

Geometry hand-authored, original. No Bethesda dragon seal, dragon-language
glyphs, or trade dress. Nordic/mountain vibe only — evocative, not derivative.
Safe to redistribute with our code.

## Pipeline

* Source of truth: `opensky/Branding/opensky-logo.svg`. 1024 canvas, 824-pt
  rounded tile centered (Apple macOS icon template proportions), mark authored
  in 512 space under a scale transform.
* `make icon` -> `tools/gen-appicon.sh` renders PNGs (16..1024) via
  `rsvg-convert` into `opensky/Assets.xcassets/AppIcon.appiconset/`. Generated
  PNGs committed — build needs no SVG toolchain.
* `Contents.json` rewritten from iOS-universal template to `mac` idiom slots
  (16/32/128/256/512 at 1x/2x, shared files across adjacent slots).
* Dependency: librsvg (Homebrew, dev-time only) — added to
  `tools/bootstrap.sh`. LGPL tool invoked as CLI; output PNGs are ours.

## Palette

* Tile `#000000`, strokes `#EAEDF0` (bone white), accent `#A8CBDE` (frost).
