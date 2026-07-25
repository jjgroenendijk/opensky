---
name: app-ui
description: Add or change OpenSky main-app UI (sidebar destinations, control panels,
  inspectors) - destination registry, panel base classes, shared components, placement
  rules, accessibility-id contract. Use before any app-shell UI work.
---

# Main-app UI framework

Workflow for the OpenSky app's own dev/verification UI (sidebar destinations,
control panels). Not the in-game Scaleform UI (issue #99). Framework lives in
`opensky/Shell/`. Full reference + placement rules:
[app-ui](/tools/app-ui.md) (`docs/tools/app-ui.md`).

Core rules (this file wins on conflict with a default habit):

## Where a new surface goes

Decide before building (config surface grows without bound):

1. New knob for an existing subsystem -> add to that subsystem's existing
   section. No new section.
2. New distinct subsystem group -> new section under the owning destination.
3. New destination only for full-height/full-content space, a distinct milestone
   surface named as a top-level path, or a section that outgrew its group.

Promotion: a section graduates to its own destination at ~8 controls, when it
needs sub-navigation, or when an acceptance names it top-level. Sections are
standalone (own sync/readout/ticker) so promotion is free — control ids unchanged.

## How to register

- Add one `DestinationDescriptor` to `DestinationRegistry.all`
  (`Shell/DestinationRegistry.swift`). Never edit the shell view controllers to
  add a destination — the registry is the single registration point. Sections:
  `world`, `developer`, `library` (`SidebarSection` order = sidebar order).
- `worldInspector` factory wires the panel's providers from
  `context.providers` (game controller conforms to all `*ControlProviding`).
- `fullContent` factory receives a `FullContentContext` (data root + startup
  error); conform the controller to `FullContentReloadable` so a Settings
  reload reaches the shell-cached instance in place.
- Add every new `Shell/` file to the `openskycli` membership-exception set in
  `opensky.xcodeproj/project.pbxproj` (app-only AppKit, excluded from CLI). Build
  BOTH targets (`make build && make cli`) — a hand-edited pbxproj is easy to get
  wrong.

## Layout + interaction invariants

Framework properties, each pinned by a test. Break one -> fix the code, not the
test.

- A collapsed section occupies its **header height and nothing more**.
  `CollapsibleSectionView` is an `NSStackView` with header + content as
  *arranged* subviews: Auto Layout only reclaims a hidden view's space when it
  is arranged. As an ordinary pinned subview it kept full height and the column
  showed blank gaps. Pinned by
  `PanelFrameworkTests/collapsedSectionOccupiesOnlyItsHeader()`.
- Never pin `heightAnchor` constants on section controls — a hard height defeats
  intrinsic sizing and survives hiding.
- **No dev behaviour reachable only by an unadvertised keystroke.** Every toggle
  is a control in a panel. A shortcut is allowed only as an accelerator for an
  existing control, registered in the main menu so it is listed. Camera/gameplay
  input (WASD/QE/Shift/Esc/mouse-look, F, G) is input, not configuration.
- Toolbar carries no `.sidebarTrackingSeparator` (it pins items to the split
  divider, so the sidebar toggle moved when clicked). Toolbar items carry
  accessibility ids like any control.
- Need a widget `PanelComponents` lacks -> add it there, never hand-roll it in a
  section.

## How to build a panel

- Subclass `InspectorPanelViewController`: `makeSections()` for a sectioned
  panel, or `makeContentViews()` + `syncControls()`/`refreshReadout()` for
  direct content.
- Subclass `PanelSectionViewController` for one control group; set
  `sectionTitle` + `sectionIdentifier`; call `finishInteraction()` from actions
  (`refocusOnMouseUpOnly: true` for continuous sliders).
- Build controls only from `PanelComponents` + `PanelMetrics` (inventory table
  in the doc). Do not hand-roll fonts/widths/timers (`InspectionTicker` owns the
  2 Hz readout).
- Spacing is a three-step scale: `rowSpacing` inside a group, `groupSpacing`
  between groups (a section's stack), `sectionSpacing` between sections. Wrap
  tightly-related controls in `PanelComponents.group([...])`.
- Panels are built on first reveal and cached by destination id — never all at
  launch.

## Accessibility-id contract

Ids are the UI-test API — never change silently. `AppSidebar` outline,
`Destination-<id>` rows, `PanelSection-<id>` headers, `<Thing>Control` /
`<Thing>StatsLabel`, toolbar `ScreenshotButton`. `make test-ui` is blocked on
this machine (TCC) -> pin ids as literal assertions in
`DestinationRegistryTests` and keep `OpenSkyUITests` correct for CI (#70).

## Verify

`make fix && make check && make build && make cli && make test`. Add/extend a
panel geometry unit test. Record the exact sidebar path in the milestone
acceptance. Same-commit docs: update [app-ui](/tools/app-ui.md) when the
framework changes.
