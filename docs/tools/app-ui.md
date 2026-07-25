---
type: Tool
title: Main-app UI framework + placement
description: How OpenSky's dev/verification UI is built — destination registry, panel
  base classes, shared components, placement rules, and the accessibility-id contract.
tags: [tool, gui, dev, ui, framework]
timestamp: 2026-07-25T00:00:00Z
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
- Sidebar map: World: World, Environment, Audio · Developer: UI Lab · Library:
  Asset Browser. Launch selects World
  (`DestinationRegistry.defaultDestinationID`). Sections come from
  `SidebarSection` (world, developer, library — `allCases` order); empty
  sections drop. Grouping is unit-tested via `AppSidebarModel`
  (`AppSidebarModelTests`).
- Three content kinds (`DestinationContent`):
  - `viewport` — the bare always-live game view, no panel. No sidebar row uses
    it: `Viewport` was a row that rendered nothing of its own and only
    collapsed the inspector column, which gave a first-time user no hint that
    any controls existed. It is now the `World` destination (camera pose +
    fly/walk selector, frame timing, scene and residency counts). The content
    kind survives as the mechanism for hiding the inspector column
    (`ShellContentViewController.showViewport()`), which becomes a View-menu
    command over whichever world destination is selected.
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
- **Panel lifetime**: world-inspector panels follow the same rule — built from
  their registry factory on first reveal, then cached by destination id for the
  life of the game controller. They used to be built all at once at launch, which
  cost a live provider graph per destination before the user had opened any of
  them; that does not scale as the roadmap adds inspectors. A Settings reload
  drops the whole cache (`replaceGame`) so panels rebuild against the new
  renderer. Pinned by
  `ShellContentCoverTests/inspectorPanelsAreBuiltOnFirstReveal()`.
- Toolbar (`unifiedCompact`, built by `AppShellViewController.makeToolbar()`):
  sidebar toggle, flexible space, screenshot. Screenshot (save-panel +
  error-sheet flow in `ScreenshotCoordinator`) is enabled only while a
  destination with `showsGameView` is active. Settings stays the Cmd+, window —
  no sidebar destination.
- The toolbar carries **no `.sidebarTrackingSeparator`**. That item pins toolbar
  items to the split divider, which put the sidebar toggle inside the sidebar
  region: collapsing the sidebar collapsed the region and the toggle slid left,
  so the button moved every time it was clicked. Laying the toolbar out
  left-to-right from a fixed origin keeps it put in both states. The toggle is a
  custom `NSToolbarItem` rather than the system `.toggleSidebar` so it carries an
  accessibility id (`SidebarToggleButton`) like every other control.
- Menu bar (`AppDelegate.makeMainMenu()` + `makeViewMenu()`): App (Settings
  Cmd+comma, Quit), View (Hide Sidebar Ctrl+Cmd+S, Show Frame HUD Opt+Cmd+H,
  Hide Inspector Opt+Cmd+I), Edit. A toolbar affordance that is also a mode gets
  a View-menu command, so it is discoverable and carries a listed shortcut. All
  three View actions resolve on the responder chain to `AppShellViewController`,
  which validates them (`NSMenuItemValidation`): each carries a checkmark
  showing which way it will go, and `Hide Inspector` greys out on a destination
  with no inspector column (a `fullContent` destination) instead of silently
  doing nothing. `Hide Inspector` is what drives the `.viewport` content kind
  over whichever world destination is selected.
- **Frame HUD** (`Shell/FrameHUDView.swift`): a small always-on readout pinned to
  the top-trailing corner of the game slot — fps, frame milliseconds, GPU or
  `n/a`, draw calls, drawn and culled instances, resident cells, footprint. It
  reads the same `FrameStatsProviding`/`SceneStatsProviding` snapshots the
  `World` panel reads, so the two surfaces cannot disagree, and refreshes on the
  shared 2 Hz `InspectionTicker`. It is an AppKit overlay and **not** a render
  pass: it needs no shader work, and it must stay out of
  `Renderer.renderOffscreen`, which feeds `openskycli screenshot`, the bench loop
  and every offscreen evidence capture — chrome encoded into the scene pass would
  burn itself into those images. Hidden (and its ticker stopped, so it costs
  nothing) whenever the user turns it off or a full-content destination covers
  the game view. The show/hide choice persists under the `frameHUD.visible`
  user default, defaulting to visible.
- A world-inspector panel is a column of collapsible sections. Each section is a
  self-contained control group with its own live readout. Selecting a world
  destination refocuses the game view so WASD/mouse capture keep working.

## Layout invariants

These are properties of the framework, not of any one panel. Each is asserted by
a unit test; a change that breaks one must fix the code, not the test.

- **A collapsed section occupies its header height and nothing more.**
  `CollapsibleSectionView` is an `NSStackView` with the header and the content as
  *arranged* subviews, because Auto Layout only reclaims a hidden view's space
  when it is arranged. Pinned as an ordinary subview with
  `content.bottom == self.bottom`, a collapsed section kept its full expanded
  height and the column reserved a blank block for it — visible as large gaps
  between collapsed sections. Pinned by
  `PanelFrameworkTests/collapsedSectionOccupiesOnlyItsHeader()`, which also
  asserts the scroll document shrinks when a section collapses. The older
  `collapsibleSectionTogglesContent()` checks only `isHidden`, which is why the
  gap shipped unnoticed; keep both.
- **The scroll document starts at the top.** The flipped document view means the
  first control sits at a small `y` (`directContentPanelScrollDocumentStartsAtTop`).
- Do not pin `heightAnchor` constants on section controls. A hard height defeats
  intrinsic sizing and survives hiding; let the control size itself.

## Interaction rules

- **No dev behaviour is reachable only by an unadvertised keystroke.** Every
  toggle is a control in a panel. A keyboard shortcut is allowed only as an
  accelerator for a control that already exists, and only when registered in the
  main menu so it is discoverable and listed. Sun shadows were an `H` keypress
  advertised by a hint note glued to the shadow section until M8; that note was
  the whole discovery mechanism, and it does not scale past a handful of knobs.
  Camera and gameplay input (`WASD`/`QE`/`Shift`/`Esc`/mouse-look, `F` activate)
  is input, not configuration, and stays on the keyboard. `G` fly-walk is the
  boundary case: it moves the camera like input but selects a mode like
  configuration, so `World > Camera` carries the selector and `G` accelerates
  it over the same renderer state.
- Widgets come from `PanelComponents`. If the one you need is missing, add it
  there rather than hand-rolling it in a section — the hand-rolled copies are
  where naming and styling drift start.

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
- `InspectionTicker` — the 2 Hz readout timer lifecycle (idempotent start).
- Control-state convention: give each knob a separate enable / force / freeze /
  inspect / reset action and a live numeric readout, rather than one overloaded
  control.

### Component inventory

Build controls only from these, so a hundred knobs still read as one panel.
Need something the list lacks? Add it here — never hand-roll it in a section.
Sections declare their controls as stored properties (no `self` at that point),
which is why widgets that need a target come as `configure*` rather than
factories.

| Factory | Use for |
|---|---|
| `heading(_:)` | Panel/section title, themed uppercase |
| `caption(_:)` | Sub-heading above a control group |
| `note(_:)` | Wrapping tertiary hint, pinned to `contentWidth` |
| `statsLabel(identifier:)` | Wrapping monospaced live readout; carries the id |
| `group(_:)` | Stacks tightly-related controls at `rowSpacing` into one unit |
| `separator()` | Full-width hairline between groups |
| `sliderRow(slider:valueLabel:)` | Slider + trailing value label |
| `labeledFieldRow(caption:captionWidth:field:)` | Caption + field, aligned column |
| `buttonRow(_:)` | Horizontal row of push buttons |
| `valueLabel(width:)` | Mono-digit readout beside a slider |
| `configureCheckbox(_:target:action:identifier:)` | Every enable/freeze/pause toggle |
| `configureButton(_:target:action:identifier:)` | Push buttons (presets, apply/reset) |
| `configureSlider(_:target:action:identifier:width:continuous:)` | Sliders |
| `configurePopUp(_:target:action:identifier:width:)` | Popups; optional width pin so a data-driven list cannot stretch the column (caller adds items) |
| `configureComboBox(_:target:action:identifier:width:)` | Editable free-form name from a short live list (a SWF movie's callbacks): common values autocomplete, anything else can still be typed |

### Spacing

`PanelMetrics` carries a three-step vertical rhythm. One value applied
everywhere made a checkbox and the slider it governs look as separate as two
whole subsystems, so the column read as loose floating blocks:

- `rowSpacing` (6) — between controls inside one group.
- `groupSpacing` (12) — between groups within a section. This is the spacing of
  a section's own stack, so whatever `makeContentViews()` returns is treated as
  a group.
- `sectionSpacing` (18) — between sections in a panel column.

Structure comes from the step between sections, not from uniform air. Wrap
tightly-related controls in `PanelComponents.group([...])` so they stay together
at the narrow step.

### Hosting a section inside a direct-content panel

A direct-content panel (`makeContentViews()`) that grows a distinct subsystem
group should not absorb it inline — the panel class hits the 250-line
type-body limit and the group loses its own readout cadence. Host it instead
(`UILabPanelViewController.hostSWFSection()`, M8.2.5):

1. Hold the group as a `PanelSectionViewController` subclass stored on the panel.
2. In `makeContentViews()`, `addChild(section)`, point
   `section.refocusAction` at a closure reading the panel's current
   `refocusAction`, and return
   `CollapsibleSectionView(title:identifier:content: section.view)` as the last
   column entry — the same header treatment a sectioned panel gets, so the
   group carries a `PanelSection-<id>` accessibility id.
3. Override `startInspecting()` / `stopInspecting()` to forward to the section,
   since the base class only fans out to `makeSections()` children.

The hosted group stays promotable: it is already a standalone section, so
moving it into its own destination later changes nothing about its control ids.

A panel can host more than one: UI Lab hosts **SWF movie** (the M8.2.5 static
selector) and **SWF runtime** (the M8.3.3 AS2 driver) in that order, because the
second runs whatever the first assigned. `SWF runtime` sits at thirteen controls,
past the ~8 promotion threshold above, and stays a hosted section anyway because
the M8.3.3 acceptance names `Developer > UI Lab` as its path. A milestone
naming the path outranks the threshold; promote it when a later milestone gives
it a path of its own. A section whose class approaches the 250-line type-body
limit splits its wiring and `@objc` actions into a `<Name>SectionInput.swift`
extension satellite (`SWFRuntimeSectionInput.swift`) rather than shedding
controls.

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
- Controls: `<Thing>Control`; readouts: `<Thing>StatsLabel`. Current UI Lab set:
  `UIOverlayEnabledControl`, `UILabSampleControl`, `UIStringsSampleControl`,
  `UIScaleControl`, `UIMenuPushControl`/`UIMenuPopControl`/`UIMenuClearControl`,
  `SWFMovieControl`, `SWFLayerEnabledControl`, and the M8.3.3 runtime set
  `SWFRuntimeStartControl`, `SWFRuntimeTickControl`,
  `SWFRuntimeTickBurstControl`, `SWFRuntimeStopControl`, `SWFRuntimeKeyControl`,
  `SWFRuntimeSendKeyControl`, `SWFRuntimePointerXControl`,
  `SWFRuntimePointerYControl`, `SWFRuntimePointerMoveControl`,
  `SWFRuntimePointerClickControl`, `SWFRuntimeCallControl`,
  `SWFRuntimeCallInvokeControl`, `SWFRuntimeClearLogControl`; readouts
  `UIStatsLabel`, `UIMenuStatsLabel`, `UIStringsStatsLabel`,
  `SWFMovieStatsLabel`, `SWFRuntimeStatsLabel`, `SWFRuntimeInvokeStatsLabel`,
  `SWFRuntimeTallyStatsLabel`. Section headers in UI Lab:
  `PanelSection-swfMovie`, `PanelSection-swfRuntime`.
- Toolbar: `ScreenshotButton` (unchanged from the old shell), `SidebarToggleButton`.
- Frame HUD overlay: `FrameHUDStatsLabel` (on the label inside `FrameHUDView`).
- World set: `CameraMovementModeControl`, `CameraCopyPoseControl`; readouts
  `CameraStatsLabel`, `FrameStatsLabel`, `SceneStatsLabel`. Section headers:
  `PanelSection-camera`, `-frame`, `-scene`.
- Environment set, so a name can be checked in one place: `SunShadowsEnabledControl`,
  `ShadowQualityControl`, `AnimationsEnabledControl`, `WeatherEnabledControl`,
  `WeatherControl`, `ClearWeatherControl`/`RainWeatherControl`/`SnowWeatherControl`,
  `WeatherTransitionsPausedControl`, `TimeOfDayControl`, `ParticlesEnabledControl`,
  `ParticlesFrozenControl`, `ParticleEmissionControl`, `PrecipitationEnabledControl`,
  `GrassEnabledControl`, `GrassDensityControl`, `GrassDistanceControl`,
  `GrassWindControl`, `LODLevel0DistanceControl`, `LODLevel1DistanceControl`,
  `LODMaximumDistanceControl`, `LODTreeDistanceControl`, `LODApplyControl`,
  `LODResetControl`; readouts `ShadowStatsLabel`, `AnimationStatsLabel`,
  `WeatherStatsLabel`, `TimeOfDayStatsLabel`, `ParticleStatsLabel`,
  `PrecipitationStatsLabel`, `GrassStatsLabel`, `LODStatsLabel`. Section headers:
  `PanelSection-shadows`, `-animation`, `-weather`, `-particles`,
  `-precipitation`, `-grass`, `-lod`.
- Audio set (World > Audio, M9.1.3): `AudioEnabledControl`,
  `AudioMasterVolumeControl`, `AudioMusicVolumeControl`,
  `AudioEffectsVolumeControl`, `AudioAmbienceVolumeControl` (the
  `Audio<Category>VolumeControl` family tracks the provisional
  `AudioCategory` list), `AudioFileControl`, `AudioPlaySelectedControl`,
  `AudioStopAllControl`; readouts `AudioStatsLabel`, `AudioSourcesStatsLabel`.
  Section headers: `PanelSection-audioOutput`, `-audioSources`.
- The convention is now uniform. The LOD and time-of-day controls used to carry
  `*Field` / `*Button` / `*Label` suffixes; they were renamed to
  `*Control` / `*StatsLabel` in one pass before the id surface grew further.
  Toolbar items are the one documented exception (`ScreenshotButton`,
  `SidebarToggleButton`) — they are window chrome, not panel controls.

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
