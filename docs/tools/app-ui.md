---
type: Tool
title: Main-app UI framework + placement
description: How OpenSky's dev/verification UI is built — destination registry, panel
  base classes, shared components, placement rules, and the accessibility-id contract.
tags: [tool, gui, dev, ui, framework]
timestamp: 2026-07-23T00:00:00Z
---

# Main-app UI framework + placement

Rules + framework for the OpenSky app's own interface — the dev/verification UI
(sidebar destinations, control panels, inspectors). Not the in-game Scaleform UI
(the vanilla SWF port, issue #99). Codifies the AGENTS.md "Main-app verification
surface" rule so new knobs stop each inventing their own pattern. Framework lives
in `opensky/Shell/` (issue #98).

Load this before adding or changing any app-shell UI.

## Scope

Every new subsystem or user-verifiable behavior gets a discoverable app surface
in the same milestone (AGENTS.md). This doc says where that surface goes and how
to build it. The durable dev/verification requirement is unchanged — a user must
be able to select/force/toggle/inspect the behavior without a CLI command.

## Shell anatomy

- Sidebar groups destinations into sections (`SidebarSection`: World, Library;
  future Developer). A destination is one sidebar row.
- Two content kinds (`DestinationContent`):
  - `worldInspector` — a controls panel shown in the leading slot beside the
    always-live game view. The MTKView never leaves the hierarchy, so rendering
    and streaming keep running while you tune knobs.
  - `fullContent` — a controller that fills the content area (e.g. Asset
    Browser).
- A world-inspector panel is a column of collapsible sections. Each section is a
  self-contained control group with its own live readout.

## Placement decision tree

Config grows without bound — decide deliberately:

1. New knob for an existing subsystem -> add it to that subsystem's existing
   section. Do not make a new section.
2. New, distinct subsystem group -> a new section under the owning destination
   (e.g. a new environment subsystem -> a new section in `Environment`).
3. New destination only when the surface needs full-height/full-content space,
   is a distinct milestone surface named as a top-level path, or a section has
   outgrown a collapsible group.

Promotion rule: a section graduates to its own destination when it exceeds
~8 controls, needs its own sub-navigation, or a milestone acceptance names it as
a top-level path. Promotion = move the `PanelSectionViewController` subclass into
a new `DestinationDescriptor`; its control accessibility ids do not change.
Sections are built to be standalone (own sync/readout/ticker) precisely so this
is free.

## How to register a destination

One `DestinationDescriptor` in `DestinationRegistry.all`
(`opensky/Shell/DestinationRegistry.swift`) — id, title, section, SF Symbol,
content. Never touch the shell view controllers to add a destination.

- A `worldInspector` factory receives a `WorldPanelContext` and wires the
  panel's providers from `context.providers` (the game controller conforms to
  every `*ControlProviding` protocol via `WorldControlProviders`). Downward:
  control action -> provider setter -> renderer. Upward: a 2 Hz ticker polls the
  provider's snapshot into a readout label. No bindings/Combine.
- Add every new `Shell/` file to the `openskycli` membership-exception set in
  `opensky.xcodeproj/project.pbxproj` (app-only AppKit, excluded from the CLI).

## Building panels

- `InspectorPanelViewController` — a full destination panel. Override
  `makeSections()` for a sectioned panel, or `makeContentViews()` +
  `syncControls()`/`refreshReadout()` for a direct-content panel (UI Lab). It
  supplies the scrolling flipped document that starts at the top — no
  hand-computed content heights.
- `PanelSectionViewController` — one control group. Override `makeContentViews`,
  `syncControls`, `refreshReadout`; set `sectionTitle` + `sectionIdentifier`.
  Call `finishInteraction()` from a control action to refresh + return focus to
  the game view; pass `refocusOnMouseUpOnly: true` for continuous sliders.
- `PanelComponents` + `PanelMetrics` — the shared control vocabulary (heading,
  caption, note, statsLabel, sliderRow, labeledFieldRow, buttonRow, slider/field
  configuration). Use these so 100 knobs still read as one panel; do not
  hand-roll fonts/widths.
- `InspectionTicker` — the 2 Hz readout timer lifecycle (idempotent start).
- Control-state convention: give each knob a separate enable / force / freeze /
  inspect / reset action and a live numeric readout, rather than one overloaded
  control.

## Accessibility-id contract

Accessibility identifiers are the UI-test API and never change silently.

- Destination rows: `WorldDestination-<id>` (via `sidebarIdentifier`).
- Section headers: `PanelSection-<sectionIdentifier>`.
- Controls: `<Thing>Control`; readouts: `<Thing>StatsLabel`.

`make test-ui` is blocked on the dev machine (TCC harness init), so the id
contract is pinned as unit assertions in `DestinationRegistryTests` — update
those literals in the same change that renames an id, and keep `OpenSkyUITests`
correct for CI re-enable (issue #70).

## Verification obligations

- Add/extend a panel geometry unit test (controls visible, within the scroll
  document) — see `EnvironmentPanelTests`, `UILabPanelTests`,
  `PanelFrameworkTests`.
- Every milestone acceptance records the exact sidebar path it verified.
- App verification supplements unit tests, probes, benchmarks, and offscreen
  evidence; it does not replace them.
