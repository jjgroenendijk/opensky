---
name: building-app-ui
description: Adds or changes OpenSky main-app UI - sidebar destinations, control panels, and
  inspectors, covering the destination registry, panel base classes, shared components,
  placement rules, and the accessibility-id contract. Use before any app-shell UI work.
---

# Main-app UI framework

The OpenSky app's own dev and verification UI: sidebar destinations and the control panels
under them. Not the in-game Scaleform UI (issue #99). The framework lives in
`opensky/Shell/`.

Full reference: `docs/tools/app-ui.md`. This skill carries the decisions you must make before
touching a file and points at the section of that doc holding each detail.

## Where a new surface goes

Decide before building, because the configuration surface grows without bound:

1. A new knob for an existing subsystem -> add it to that subsystem's existing section. No
   new section.
2. A new distinct subsystem -> a new section under the owning destination.
3. A new destination only for full-height or full-content space, a distinct milestone surface
   named as a top-level path, or a section that has outgrown its destination.

A section is promoted to its own destination at roughly 8 controls, when it needs
sub-navigation, or when a milestone acceptance names it top-level. Sections are standalone
(each owns its sync, readout, and ticker), so promotion is free and control ids do not
change. A milestone-named path outranks the threshold — see "Sectioned UI Lab and
direct-content panels" in `docs/tools/app-ui.md`.

## How to register

- Add one `DestinationDescriptor` to `DestinationRegistry.all`
  (`Shell/DestinationRegistry.swift`). Never edit the shell view controllers to add a
  destination — the registry is the single registration point. Sidebar sections are `world`,
  `developer`, and `library` (`SidebarSection` order is sidebar order).
- A `worldInspector` factory wires the panel's providers from `context.providers`; a
  `fullContent` factory receives a `FullContentContext`, and its controller conforms to
  `FullContentReloadable` so a Settings reload reaches the shell-cached instance in place.
- Register provider-backed `DestinationOverrideActions` beside each mutable
  `DestinationDescriptor`. Sidebar aggregation and Reset all use those actions and never
  construct an unopened panel. Details in "Override provenance and reset" in
  `docs/tools/app-ui.md`.
- Add every new `Shell/` file to the `openskycli` membership-exception set in
  `opensky.xcodeproj/project.pbxproj` (app-only AppKit, excluded from the CLI), then build
  BOTH targets (`make build && make cli`). A hand-edited `project.pbxproj` is easy to get
  wrong.

## Invariants you cannot break

Each is pinned by a unit test. Break one -> fix the code, not the test. The reasoning behind
each lives in "Layout invariants" and "Interaction rules" in `docs/tools/app-ui.md`.

- A collapsed section occupies its header height and nothing more: `CollapsibleSectionView`
  keeps header and content as *arranged* subviews of an `NSStackView`, because Auto Layout
  reclaims a hidden view's space only when it is arranged.
- Never pin `heightAnchor` constants on section controls; a hard height defeats intrinsic
  sizing and survives hiding.
- No dev behaviour is reachable only by an unadvertised keystroke. Every toggle is a control
  in a panel; a shortcut is allowed only as an accelerator for an existing control,
  registered in the main menu so it is listed. Camera and gameplay input is input, not
  configuration.
- Panels are built on first reveal and cached by destination id, never all at launch.

## How to build a panel

Subclass `InspectorPanelViewController` for a destination panel and
`PanelSectionViewController` for one control group. Build controls only from
`PanelComponents` and `PanelMetrics` — if the widget you need is missing, add it there rather
than hand-rolling it in a section, and do not hand-roll fonts, widths, or timers
(`InspectionTicker` owns the 2 Hz readout). The base-class hooks, the component inventory
table, and the three-step spacing scale are in "Building panels" in `docs/tools/app-ui.md`.

## Accessibility-id contract

Ids are the UI-test API — never change one silently. `AppSidebar` outline, `Destination-<id>`
rows, `PanelSection-<id>` headers, `<Thing>Control` and `<Thing>StatsLabel`, section state
`PanelSection-<id>-OverrideIndicator` and `PanelSection-<id>-ResetControl`, destination state
`Destination-<id>-OverrideIndicator`, menu item `ResetAllOverridesCommand`, toolbar
`ScreenshotButton`.

Pin the ids as literal assertions in `DestinationRegistryTests` and update those literals in
the same change that renames an id. Keep `openskyUITests` correct even where the UI-test
harness cannot run locally (`docs/tools/environment.md`).

## Verify

`make fix && make check && make build && make cli && make test`, plus a new or extended panel
geometry unit test. At milestone acceptance, write the record defined by
`docs/tools/sidebar-acceptance.md` — sidebar path, `Destination-<id>`, control ids, readout
id, covering tests — into the subsystem page and that page's ledger. Those tests are the
evidence; A/B captures are optional, stay in gitignored `logs/`, and are never committed.
Same-commit docs: update `docs/tools/app-ui.md` when the framework changes.
