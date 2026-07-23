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
  add a destination — the registry is the single registration point.
- `worldInspector` factory wires the panel's providers from
  `context.providers` (game controller conforms to all `*ControlProviding`).
- Add every new `Shell/` file to the `openskycli` membership-exception set in
  `opensky.xcodeproj/project.pbxproj` (app-only AppKit, excluded from CLI). Build
  BOTH targets (`make build && make cli`) — a hand-edited pbxproj is easy to get
  wrong.

## How to build a panel

- Subclass `InspectorPanelViewController`: `makeSections()` for a sectioned
  panel, or `makeContentViews()` + `syncControls()`/`refreshReadout()` for
  direct content.
- Subclass `PanelSectionViewController` for one control group; set
  `sectionTitle` + `sectionIdentifier`; call `finishInteraction()` from actions
  (`refocusOnMouseUpOnly: true` for continuous sliders).
- Build controls only from `PanelComponents` + `PanelMetrics`. Do not hand-roll
  fonts/widths/timers (`InspectionTicker` owns the 2 Hz readout).

## Accessibility-id contract

Ids are the UI-test API — never change silently. `WorldDestination-<id>` rows,
`PanelSection-<id>` headers, `<Thing>Control` / `<Thing>StatsLabel`. `make
test-ui` is blocked on this machine (TCC) -> pin ids as literal assertions in
`DestinationRegistryTests` and keep `OpenSkyUITests` correct for CI (#70).

## Verify

`make fix && make check && make build && make cli && make test`. Add/extend a
panel geometry unit test. Record the exact sidebar path in the milestone
acceptance. Same-commit docs: update [app-ui](/tools/app-ui.md) when the
framework changes.
