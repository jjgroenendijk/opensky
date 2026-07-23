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

## Shell anatomy (as built, issue #98 PR 2)

- One `NSSplitViewController` shell (`AppShellViewController`): source-list
  sidebar (`AppSidebarViewController`, `NSOutlineView` with non-selectable
  group rows) + layered content (`ShellContentViewController`). The old
  segmented World/Asset Browser mode switch is gone.
- Sidebar map: World: Viewport, Environment · Developer: UI Lab · Library:
  Asset Browser. Launch selects Viewport
  (`DestinationRegistry.defaultDestinationID`). Sections come from
  `SidebarSection` (world, developer, library — `allCases` order); empty
  sections drop. Grouping is unit-tested via `AppSidebarModel`
  (`AppSidebarModelTests`).
- Three content kinds (`DestinationContent`):
  - `viewport` — the bare always-live game view, no panel.
  - `worldInspector` — a controls panel shown in the leading 300pt slot beside
    the always-live game view.
  - `fullContent` — a controller that covers the content area (Asset Browser).
    The MTKView stays attached underneath, but while covered it is hidden and
    its draw loop paused (`ShellContentViewController.setGameCovered`), and the
    full-content slot draws an opaque themed backdrop. Owner decision
    2026-07-23: the world must not render behind the Asset Browser. This
    reverses the original issue #98 low-rate choice (10 fps covered so the
    streamer stayed warm); uncovering resumes the draw loop and the streamer
    re-warms on the next frame. Pinned by
    `ShellContentCoverTests/coveredGameViewIsHiddenAndPaused()`.
- Full-content controllers are built lazily from their registry factory, which
  receives a `FullContentContext` (data root + startup error), and cached
  forever by the shell — catalog/filter/selection survive destination changes.
  A Settings reload calls `FullContentReloadable.reloadFullContent(context:)`
  on each cached controller in place.
- Toolbar (`unifiedCompact`, built by `AppShellViewController.makeToolbar()`):
  sidebar toggle, tracking separator, flexible space, screenshot. Screenshot
  (save-panel + error-sheet flow in `ScreenshotCoordinator`) is enabled only
  while a destination with `showsGameView` is active. Settings stays the
  Cmd+, window — no sidebar destination.
- A world-inspector panel is a column of collapsible sections. Each section is a
  self-contained control group with its own live readout. Selecting a world
  destination refocuses the game view so WASD/mouse capture keep working.

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
- A `fullContent` factory receives a `FullContentContext` (data root + startup
  error). Conform the controller to `FullContentReloadable` so a Settings
  reload reaches the cached instance in place instead of rebuilding it.
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

## Theme

The shell is a committed dark, Skyrim-inspired design (owner request
2026-07-23). All tokens live in `opensky/Shell/Theme.swift`; the app forces
dark appearance at launch (`AppDelegate`), so system controls sit on the same
palette in every environment.

- Surfaces: `Theme.windowBackground` (window + full-content backdrop),
  `Theme.panelBackground` (inspector-panel slot), `Theme.raisedBackground`
  (text/image wells).
- Ink: `Theme.parchment` (primary), `Theme.parchmentDim` (readouts/status),
  `Theme.gold` (accent — also the asset-catalog `AccentColor`, so selection
  and focus tint match), `Theme.divider` (hairlines via `Theme.hairline()`).
- Type: headings/section titles go through
  `Theme.headingAttributed(_:size:color:)` — uppercase, tracked, in
  `Theme.displayFont` (macOS-bundled Futura Condensed Medium with a system
  fallback; nothing is shipped, so the fallback path is a hard requirement and
  is unit-tested in `ThemeTests`).
- Rules: never hand-pick colors or heading fonts in panels or shell code — take
  them from `Theme`. `PanelComponents.heading`/`caption`/`statsLabel` and
  `CollapsibleSectionView` already apply the treatment, so sectioned panels get
  the look for free. Legal boundary as everywhere: no Bethesda fonts, art, or
  extracted UI assets; the vibe comes from palette + typography only.

## Accessibility-id contract

Accessibility identifiers are the UI-test API and never change silently.

- Sidebar outline: `AppSidebar`; destination rows: `Destination-<id>` (via
  `sidebarIdentifier`). PR 2 renamed the rows from `WorldDestination-<id>` and
  replaced the `WorldSidebar` table + `ModeSwitcher` radios with the outline.
- Section headers: `PanelSection-<sectionIdentifier>`.
- Controls: `<Thing>Control`; readouts: `<Thing>StatsLabel`.
- Toolbar screenshot: `ScreenshotButton` (unchanged from the old shell).

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
