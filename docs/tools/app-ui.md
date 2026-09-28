---
type: Tool
title: Main-app UI framework and placement
description: How OpenSky's developer and verification UI is built - shell anatomy, layout
  invariants, interaction rules, override provenance, placement rules, registering a destination,
  building panels, the theme, and the accessibility id contract.
tags: [tool, gui, dev, ui, framework]
---

# Main-app UI framework and placement

This page covers the app's own interface: sidebar destinations, control panels, and inspectors. It
is not the in-game UI, which is vanilla SWF movies ([SWF layer](/rendering/swf-layer.md)). The
framework is in `Sources/OpenSky/Shell/`. `AGENTS.md` requires that every user-visible behavior
can be selected, forced, toggled, or inspected from the sidebar without a CLI command. This page
says where that surface goes and how to build it.

## Shell anatomy

- One split view: a source list sidebar and a content area. Sidebar sections come from
  `SidebarSection` in order (World, Developer, Library), and an empty section is dropped. Launch
  selects World.
- Three content kinds:
  - A world inspector is a controls panel in a 300 point column beside the live game view.
  - Full content covers the content area, like the Asset Browser. While covered, the game view is
    hidden and its draw loop paused, so the world does not render behind it. Uncovering resumes it,
    and streaming warms up again on the next frame.
  - The bare viewport has no row of its own. A row that drew nothing and only hid the inspector gave
    a new user no hint that controls existed. It survives as the View menu command that hides the
    inspector column.
- Panels are built on first reveal and cached by destination id. Building them all at launch cost a
  live provider graph per destination before the user opened any. A Settings reload drops the cache,
  so panels rebuild against the new renderer. Full-content controllers are cached for good and
  reloaded in place.
- The toolbar has the sidebar toggle, a flexible space, and the screenshot button. It has no
  `.sidebarTrackingSeparator`: that item pinned the toggle inside the sidebar region, so the button
  moved every time it was clicked. The toggle is a custom item so it can carry an accessibility id.
  Settings is the Cmd+, window, not a sidebar row.
- The View menu has Hide Sidebar, Show Frame HUD, Hide Inspector, and Reset all overrides.
- The frame HUD is a small AppKit overlay in the corner of the game view: fps, frame time, GPU time,
  draw calls, instances, resident cells, and memory. It reads the same snapshots as the World panel,
  so the two cannot disagree. It is not a render pass, so it stays out of offscreen renders.
- Selecting a world destination gives focus back to the game view, so keyboard and mouse capture
  keep working.

## Layout invariants

Each rule is checked by a unit test. A change that breaks one fixes the code, not the test.

- A collapsed section takes its header height and nothing more. `CollapsibleSectionView` is an
  `NSStackView` with the header and content as arranged subviews, because Auto Layout reclaims a
  hidden view's space only when it is arranged. Pinned as a plain subview, a collapsed section kept
  its full height and left a blank gap. A test that only checks `isHidden` missed that gap, so keep
  the test that measures the height too.
- The scroll document starts at the top.
- Do not pin `heightAnchor` constants on section controls. A fixed height defeats intrinsic sizing
  and survives hiding.

## Interaction rules

- No developer behavior is reachable only by an unlisted keystroke. Every toggle is a control in a
  panel. A shortcut is allowed only as an accelerator for an existing control, registered in the main
  menu so it is listed. A hint note beside one section does not scale past a few knobs. Camera and
  gameplay input (movement, mouse look, activate) is input, not configuration, and stays on the
  keyboard. The fly and walk key is the edge case: it moves the camera like input but picks a mode
  like configuration, so the World panel has the selector and the key accelerates it.
- Widgets come from `PanelComponents`. If one is missing, add it there instead of hand-making it in
  a section, because hand-made copies are where naming and style drift start.

## Override provenance and reset

Every mutable section implements `isOverridden` and `resetToDefaults()` against its live provider. A
section keeps the base false and no-op only when its controls leave no provider state behind.

Override state comes from the provider, never from widget values. Automatic weather shows why: the
weather popup can show a real weather while the provider is still automatic. It also lets the
sidebar show an override before the panel was ever opened.

An overridden section shows a gold dot and a Reset control in its header, so collapsing it never
hides the warning or its fix. The section's 2 Hz ticker updates both with the readout, so override
display adds no timer.

Reset restores the defaults and then syncs the visible controls. Settings saved in user defaults are
removed, and distant LOD removes its override keys so the Skyrim INI values apply again. Collapse
state is presentation, not an override, and Reset keeps it.

Each destination row shows a dot when any of its sections is overridden, through override actions
stored beside the registry entry, so an unopened panel can show a dot without being built.
`View > Reset all overrides` runs every destination's action, opened or not, and then syncs cached
panels.

## Placement

The number of settings grows without end, so decide on purpose:

1. A new knob for an existing subsystem goes in that subsystem's section. No new section.
2. A new, separate subsystem gets a new section under the destination that owns it.
3. A new destination only when the surface needs the full height or content area, is a separate
   surface named as a top-level path, or a section has outgrown a collapsible group.

A section becomes its own destination at about 8 controls, when it needs its own navigation, or
when an acceptance names it as a top-level path. Its control ids do not change. Sections are built to
stand alone (their own sync, readout, and ticker), so moving one is free.

## Registering a destination

Add one `DestinationDescriptor` (id, title, section, SF Symbol, content kind) to
`DestinationRegistry.all`. Never touch the shell view controllers to add a destination. `all` joins
several arrays kept in the registry file and its satellite files, because one literal passed the
type length limit. The arrays join in sidebar order.

- A world inspector factory gets a context and wires the panel's providers from
  `context.providers`. Actions go down: control, provider setter, renderer. Readouts go up: a 2 Hz
  ticker polls the provider's snapshot into a label. No bindings or Combine.
- A mutable destination also stores override actions beside its descriptor, which call the same
  provider-backed helpers as the panel. Do not build a panel to read its state.
- A full-content factory gets the data root and any startup error. The controller conforms to
  `FullContentReloadable`, so a Settings reload reaches the cached instance.
- App-only AppKit code goes under `Sources/OpenSky/`, which only the app target builds.

## Building panels

- `InspectorPanelViewController` is a whole destination panel. Override `makeSections()` for a
  sectioned panel, or `makeContentViews()`, `syncControls()`, and `refreshReadout()` for a panel of
  plain content. It supplies the scrolling document, so no content heights are computed by hand.
- `PanelSectionViewController` is one control group. Override `makeContentViews`, `syncControls`,
  `refreshReadout`, `isOverridden`, and `resetToDefaults`, and set `sectionTitle` and
  `sectionIdentifier`. Call `finishInteraction()` from an action to refresh and give focus back to
  the game. Continuous sliders pass `refocusOnMouseUpOnly: true`.
- `InspectionTicker` runs the 2 Hz readout timer.
- Each section normally runs its own ticker. A panel whose sections all read one costly value sets
  `sectionsTickIndependently` to false, runs the only ticker, builds that value once in
  `refreshSections()`, and hands it down.

### Components

Build controls only from `PanelComponents`, so a hundred knobs still read as one panel. Sections
declare controls as stored properties, where `self` does not exist yet, so widgets that need a
target come as `configure*` calls rather than factories: `configureCheckbox`, `configureButton`,
`configureSlider`, `configurePopUp` (with an optional width pin, so a long list cannot stretch the
column), and `configureComboBox` (a free-form name with suggestions, such as a movie's callbacks).
The layout helpers are `heading`, `caption`, `note`, `statsLabel`, `group`, `separator`, `sliderRow`,
`labeledFieldRow`, `buttonRow`, and `valueLabel`.

### Spacing

`PanelMetrics` has three vertical steps: `rowSpacing` (6) between controls in one group,
`groupSpacing` (12) between groups in a section, and `sectionSpacing` (18) between sections. One
value everywhere made a checkbox and its slider look as far apart as two subsystems. Wrap related
controls in `PanelComponents.group([...])` so they stay at the narrow step.

### Sectioned UI Lab and direct-content panels

A panel whose controls leave provider state behind is a sectioned panel, so the standard fan-out
handles ticker lifetime, override state, reset, and refocus. Do not host a section by hand. A panel
of plain content fits only a truly full-column surface; if it gains a separate control group,
convert it to `makeSections()`.

A path an acceptance names outranks the promotion threshold: UI Lab's SWF runtime section stays under
`Developer > UI Lab` though it has more than 8 controls. A section class near the type body limit moves
its wiring and `@objc` actions into a `<Name>SectionInput.swift` extension instead of dropping
controls.

## Theme

The shell has a fixed dark design inspired by Skyrim. All tokens are in
`Sources/OpenSky/Shell/Theme.swift`, and the app forces dark appearance, so system controls
match. Take every color and heading font from `Theme`: surfaces, parchment ink, gold accent (also
the asset catalog `AccentColor`), and dividers. Headings are uppercase and tracked in Futura
Condensed Medium, which macOS ships, with a system fallback. Nothing is bundled, so the fallback
must work. No Bethesda fonts, art, or UI assets: the look comes from color and type only.

## Accessibility id contract

Accessibility ids are the UI test API and never change silently.

| Element | Id |
| --- | --- |
| Sidebar outline | `AppSidebar` |
| Destination row | `Destination-<id>` |
| Section header | `PanelSection-<sectionIdentifier>` |
| Control and readout | `<Thing>Control` and `<Thing>StatsLabel` |
| Destination and section override dots | `Destination-<id>-OverrideIndicator`, `PanelSection-<sectionIdentifier>-OverrideIndicator` |
| Section reset | `PanelSection-<sectionIdentifier>-ResetControl` |
| Reset all menu item | `ResetAllOverridesCommand` |
| Toolbar | `ScreenshotButton`, `SidebarToggleButton` (window chrome, the one exception to the suffix rule) |
| Frame HUD | `FrameHUDStatsLabel` |

Some ids are built at run time, such as `Audio<Category>VolumeControl`. The ids are pinned as literal
assertions in `DestinationRegistryTests` and the panel tests, which are the list. Update those
literals in the same change that renames an id, and keep `OpenSkyUITests` correct wherever the UI
test harness runs ([environment](/tools/environment.md)).

## Verification

- Add or extend a panel geometry test: controls visible and inside the scroll document.
- Acceptance writes the record defined on the [sidebar acceptance](/tools/sidebar-acceptance.md) page
  into the closing PR or issue, not into `docs/`.
- A/B captures are optional, stay in `logs/`, and are never committed, because a rendered frame holds
  the user's game assets.
