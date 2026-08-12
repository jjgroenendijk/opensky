---
type: Tool
title: Main-app UI framework + placement
description: How OpenSky's dev/verification UI is built — destination registry, panel
  base classes, shared components, placement rules, and the accessibility-id contract.
tags: [tool, gui, dev, ui, framework]
timestamp: 2026-07-28T00:00:00Z
---

# Main-app UI framework + placement

Rules + framework for the OpenSky app's own interface — the dev/verification UI
(sidebar destinations, control panels, inspectors). Not the in-game Scaleform UI
(the vanilla SWF port, issue #99). Codifies the AGENTS.md "Main-app verification
surface" rule so new knobs stop each inventing their own pattern. Framework lives
in `opensky/App/Shell/` (issue #98).

Load this before adding or changing any app-shell UI.

## Contents

- Scope
- Shell anatomy — split view, sidebar, destinations, HUD
- Layout invariants — collapsed sections, scroll document, no pinned heights
- Interaction rules — discoverability, `PanelComponents` ownership
- Override provenance and reset — the section contract hooks
- Placement decision tree — where a new surface goes, promotion threshold
- How to register a destination — `DestinationRegistry`, target membership
- Building panels — base classes, component inventory, spacing, UI Lab
- Theme
- Accessibility-id contract — the UI-test API
- Verification obligations — geometry tests and the acceptance record

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
- Sidebar map: World: World, Environment, HUD & Interaction, System Menu, Audio,
  Runtime State, Scripts · Developer: UI Lab · Library: Asset Browser, Load Order
  ([plugins.txt](/formats/plugins-txt.md)). Launch selects World
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
- **Override provenance**: each mutable section reports whether its live
  provider differs from the section defaults and can restore those defaults.
  A gold dot and Reset control in the section header stay visible even while
  its content is collapsed. Destination rows aggregate the same state through
  provider-backed `DestinationOverrideActions` stored beside the registry
  descriptor, so an unopened panel can show a dot without being constructed.
  Resetting cached panels resyncs their controls after the provider changes.
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
  Hide Inspector Opt+Cmd+I, Reset all overrides), Edit. The View actions
  resolve on the responder chain to `AppShellViewController`, which validates
  them (`NSMenuItemValidation`). Modes carry checkmarks, `Hide Inspector`
  greys out on a destination with no inspector column, and Reset all greys out
  when every provider is at its defaults. `Hide Inspector` drives the
  `.viewport` content kind over whichever world destination is selected.
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

## Override provenance and reset

`PanelSectionViewController` defines two mandatory section-contract hooks:
`var isOverridden: Bool` and `func resetToDefaults()`. Every mutable section
implements both against its live provider. The base false/no-op implementation
is deliberate only for a readout-only or action-only section whose controls do
not leave provider state behind.

Override state comes from the provider, never from the current widget values.
That distinction matters for controls such as automatic weather: the current
weather popup can show a real weather while the provider is still in automatic
mode. It also lets the sidebar report an override before its panel has ever
been opened.

`CollapsibleSectionView` renders a `Theme.gold` dot and Reset control whenever
its section is overridden. Both are part of the header, so collapsing the
content never hides the warning or its remedy. The section's existing 2 Hz
`InspectionTicker` republishes the state alongside the readout; override chrome
must not introduce another timer.

Reset restores the section's semantic defaults and then resyncs visible
controls and readouts. Shadow quality and time of day remove their persisted
defaults keys, and distant LOD removes the OpenSky LOD override keys so Skyrim
INI values become authoritative again. Section collapse state is presentation
state, not an override, and Reset preserves it.

The sidebar dot aggregates every mutable section under its exact path:
`World > World`, `World > Environment`, `World > HUD & Interaction`,
`World > System Menu`, `World > Audio`, `World > Runtime State`,
`World > Scripts`, or `Developer > UI Lab`.
`View > Reset all overrides` invokes
every registered destination action, including unopened destinations, and then
resyncs cached panels.

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
(`opensky/App/Shell/DestinationRegistry.swift`) — id, title, section, SF Symbol,
content. Never touch the shell view controllers to add a destination.

`all` is assembled from three arrays rather than written as one literal, because
adding the M16 gate's destination (issue #203) took the enum body past the
strict-lint type-length cap: `simulationDestinations` and `sessionDestinations`
stay in that file, and `menuDestinations` — the System, Inventory and Container
menus — lives in `DestinationRegistryMenus.swift` beside the override actions
that were split out for the same reason. The three concatenate in sidebar order,
and the registry is still the single registration point: nothing outside those
two files registers a destination.

- A `worldInspector` factory receives a `WorldPanelContext` and wires the
  panel's providers from `context.providers` (the game controller conforms to
  every `*ControlProviding` protocol via `WorldControlProviders`). Downward:
  control action -> provider setter -> renderer. Upward: a 2 Hz ticker polls the
  provider's snapshot into a readout label. No bindings/Combine.
- A mutable destination also stores `DestinationOverrideActions` beside its
  descriptor. Its status and reset closures call the same provider-backed
  section helpers as the panel. This is the lightweight path used by sidebar
  dots and Reset all; do not build a panel to inspect its state.
- A `fullContent` factory receives a `FullContentContext` (data root + startup
  error). Conform the controller to `FullContentReloadable` so a Settings
  reload reaches the cached instance in place instead of rebuilding it.
- Every new `Shell/` file goes under `opensky/App/Shell/`. The app target is the only one
  that synchronizes `opensky/App/`, so app-only AppKit code stays out of `openskycli` with
  no project-file edit (issue #336).

## Building panels

- `InspectorPanelViewController` — a full destination panel. Override
  `makeSections()` for a sectioned panel, or `makeContentViews()` +
  `syncControls()`/`refreshReadout()` for a direct-content panel. It
  supplies the scrolling flipped document that starts at the top — no
  hand-computed content heights.
- `PanelSectionViewController` — one control group. Override `makeContentViews`,
  `syncControls`, `refreshReadout`, `isOverridden`, and `resetToDefaults`; set
  `sectionTitle` + `sectionIdentifier`. Readout/action-only sections may
  deliberately inherit the base false/no-op override hooks. Call
  `finishInteraction()` from a control action to refresh + return focus to the
  game view; pass `refocusOnMouseUpOnly: true` for continuous sliders.
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

### Sectioned UI Lab and direct-content panels

UI Lab began as direct controls with two manually hosted SWF sections. Override
aggregation made that split misleading: its unsectioned controls also leave
provider state behind. It is now a normal sectioned panel, in this order:
**UI foundation**, **SWF movie**, **SWF runtime**. Their headers are
`PanelSection-uiFoundation`, `PanelSection-swfMovie`, and
`PanelSection-swfRuntime`; the existing control identifiers did not change.

The runtime section remains under `Developer > UI Lab` even though its control
count exceeds the usual promotion threshold, because the M8.3.3 acceptance
names that exact path. A milestone-named path outranks the threshold. A section
whose class approaches the 250-line type-body limit splits its wiring and
`@objc` actions into a `<Name>SectionInput.swift` extension satellite
(`SWFRuntimeSectionInput.swift`) rather than shedding controls.

Direct-content panels remain appropriate for a genuinely full-column surface.
If one later gains a distinct control group, convert it to normal
`makeSections()` composition. Do not manually host a section: the standard
panel fan-out owns ticker lifecycle, override aggregation, reset, and refocus
wiring.

`World > HUD & Interaction` is another normal sectioned panel. **Elements**
(`PanelSection-hudElements`) owns reversible presentation overrides;
**Target** (`PanelSection-hudTarget`) is read-only live diagnostics. The
milestone names the destination path, so its eight controls do not get folded
into World or UI Lab.

`World > System Menu` (M8.5.1) follows the same shape. **Menu**
(`PanelSection-systemMenu`) opens the engine menu stack and drives the
Resume/Settings/Quit selector; **Settings** (`PanelSection-systemMenuSettings`)
carries the two placeholders the milestone surfaces. Both count as overrides —
an open menu pauses world simulation and an enabled movie takes the SWF layer
from the gameplay HUD, so the sidebar dot must show either. The menu has no
opening keystroke: `Esc` already releases mouse capture in gameplay, and a
key-only trigger would break the no-unadvertised-keystroke rule. See
[system menu](/engine/system-menu.md).

## Theme

The shell is a committed dark, Skyrim-inspired design (owner request
2026-07-23). All tokens live in `opensky/App/Shell/Theme.swift`; the app forces
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
- Override chrome: destination dots
  `Destination-<id>-OverrideIndicator`; section dots
  `PanelSection-<sectionIdentifier>-OverrideIndicator`; section Reset controls
  `PanelSection-<sectionIdentifier>-ResetControl`; View-menu Reset all item
  `ResetAllOverridesCommand`.
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
  `PanelSection-uiFoundation`, `PanelSection-swfMovie`,
  `PanelSection-swfRuntime`.
- Toolbar: `ScreenshotButton` (unchanged from the old shell), `SidebarToggleButton`.
- Frame HUD overlay: `FrameHUDStatsLabel` (on the label inside `FrameHUDView`).
- World set: `CameraMovementModeControl`, `CameraCopyPoseControl`; readouts
  `CameraStatsLabel`, `FrameStatsLabel`, `SceneStatsLabel`. Section headers:
  `PanelSection-camera`, `-frame`, `-scene`. Extended by trigger volumes
  (M11.2.3): `TriggerLogClearControl`; readouts `TriggerVolumeStatsLabel`,
  `TriggerEventStatsLabel`; section header `PanelSection-triggerVolumes`. It
  belongs here, not under a destination of its own, because occupancy is only
  tested in walk mode and the fly/walk selector is one section above it. See
  [static collision world](/engine/collision-world.md).
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
  `AudioMasterVolumeControl`, `AudioEffectsVolumeControl`,
  `AudioVoiceVolumeControl`, `AudioMusicVolumeControl`,
  `AudioFootstepsVolumeControl` (the `Audio<Category>VolumeControl` family
  tracks the four menu-visible vanilla SNCT categories), `AudioFileControl`,
  `AudioPlaySelectedControl`,
  `AudioStopAllControl`; readouts `AudioStatsLabel`, `AudioSourcesStatsLabel`.
  Extended by the world sound director (M9.2.2): `AudioSfxEnabledControl`,
  `AudioAmbienceEnabledControl`, `AudioStopAmbienceControl`; readout
  `AudioSfxStatsLabel`. Extended again by the music director (M9.2.3):
  `AudioMusicEnabledControl`, `AudioMusicTypeControl`, `AudioStopMusicControl`;
  readout `AudioMusicStatsLabel`. Section headers:
  `PanelSection-audioOutput`, `-audioSources`, `-audioSfx`, `-audioMusic`.
  The Voice section moved to `World > Dialogue & Voice` with the M17 gate
  (M17.8); everything routed to the voice submix still reports in
  `AudioSourcesStatsLabel` here.
- Dialogue & Voice set (World > Dialogue & Voice, M17.8), the milestone's own
  destination assembling the four sections its sub-issues built:
  `DialogueOpenControl`, `DialogueLeaveControl`, `DialogueUpControl`,
  `DialogueDownControl`, `DialogueChooseControl`,
  `DialogueCameraForceControl`, `DialogueCameraTargetControl`,
  `DialogueCameraOverlayControl`, `AudioVoiceFilterControl`,
  `AudioVoiceFilterApplyControl`, `AudioVoiceFileControl`,
  `AudioVoicePlayControl`, `LipSyncEnabledControl`, `FaceMorphTargetControl`,
  `MorphWeightControl`, `FaceMorphResetControl`; readouts
  `DialogueTopicsStatsLabel`, `DialogueConditionsStatsLabel`,
  `DialogueMovieStatsLabel`, `DialogueCameraStatsLabel`,
  `DialogueCameraSpeakerStatsLabel`, `AudioVoiceStatsLabel`,
  `VoiceSourceStatsLabel`, `LipSyncStatsLabel`, `FaceMorphStatsLabel`. Section
  headers: `PanelSection-dialogue`, `-dialogueCamera`, `-audioVoice`,
  `-faceMorphs`. The control identifiers kept the prefixes their own items
  pinned — `AudioVoice*` for the submix, `MorphWeightControl` for the weight —
  because they are the UI-test contract and the move changed no behaviour.
- HUD set (World > HUD & Interaction, M8.4.3):
  `HUDLayerEnabledControl`, `HUDCrosshairControl`, `HUDMetersControl`,
  `HUDCompassControl`, `HUDMarkersControl`, `HUDPromptControl`,
  `HUDPlaceholderTextControl`, `HUDScaleControl`; readouts `HUDElementsStatsLabel`,
  `HUDTargetStatsLabel`. Section headers: `PanelSection-hudElements`,
  `PanelSection-hudTarget`.
- System menu set (World > System Menu, M8.5.1): `SystemMenuOpenControl`,
  `SystemMenuResumeControl`, `SystemMenuUpControl`, `SystemMenuDownControl`,
  `SystemMenuActivateControl`, `SystemMenuMovieControl`,
  `SystemMenuMasterVolumeControl`; readouts `SystemMenuStatsLabel`,
  `SystemMenuDataRootStatsLabel`, `SystemMenuSettingsStatsLabel`. Section
  headers: `PanelSection-systemMenu`, `PanelSection-systemMenuSettings`.
- Runtime State set (World > Runtime State, M10.1.5): `RuntimeStateTargetControl`,
  `RuntimeStateDisableControl`, `RuntimeStateEnableControl`,
  `RuntimeStateNudgeControl`, `RuntimeStateResetTargetControl`,
  `RuntimeStateResetAllControl`, `RuntimeStateSlotControl`,
  `RuntimeStateSaveControl`, `RuntimeStateLoadControl`; readouts
  `RuntimeStateStatsLabel`, `RuntimeStateJournalStatsLabel`,
  `RuntimeStateChangeStatsLabel`, `RuntimeStateResetStatsLabel`,
  `RuntimeStateSaveStatsLabel`. Section headers: `PanelSection-runtimeStateInspect`,
  `-runtimeStateChange`, `-runtimeStateReset`, `-runtimeStateSave`. See
  [runtime state](/engine/runtime-state.md).
- Scripts set (World > Scripts, M11.2.5): `ScriptPauseControl`, `ScriptStepControl`,
  `ScriptBurstControl`; readouts `ScriptInstancesStatsLabel`, `ScriptEventsStatsLabel`,
  `ScriptSchedulerStatsLabel`, `ScriptNativeTallyStatsLabel`. Section headers:
  `PanelSection-scriptInstances`, `-scriptEvents`, `-scriptScheduler`,
  `-scriptNativeTally`. The scheduler section is the only mutable one, so it is the only
  one carrying override chrome: `PanelSection-scriptScheduler-OverrideIndicator`,
  `PanelSection-scriptScheduler-ResetControl`, and the destination dot
  `Destination-scripts-OverrideIndicator`. See [Papyrus VM](/engine/papyrus-vm.md).
- The convention is now uniform. The LOD and time-of-day controls used to carry
  `*Field` / `*Button` / `*Label` suffixes; they were renamed to
  `*Control` / `*StatsLabel` in one pass before the id surface grew further.
  Toolbar items are the one documented exception (`ScreenshotButton`,
  `SidebarToggleButton`) — they are window chrome, not panel controls.

The id contract is pinned as unit assertions in `DestinationRegistryTests` —
update those literals in the same change that renames an id, and keep
`openskyUITests` correct so it passes wherever the UI-test harness runs. Whether
`make test-ui` works locally is environment state, recorded in
[local environment](/tools/environment.md).

## Verification obligations

- Add/extend a panel geometry unit test (controls visible, within the scroll
  document) — see `EnvironmentPanelTests`, `UILabPanelTests`,
  `PanelFrameworkTests`.
- Every milestone acceptance writes one record in the fixed format defined by
  the [sidebar verification convention](/tools/sidebar-acceptance.md): sidebar
  path, `Destination-<id>`, the control ids exercised, the readout id that
  proves the change, the deterministic tests that cover it, and an optional
  local A/B note. The record goes in the subsystem page and in that page's
  ledger, in the same commit as the work.
- Those deterministic tests are the evidence. A changed-pixel A/B capture is
  optional and local-only: captures live in the gitignored `logs/` directory
  and are never committed, because a rendered frame embeds the user's Bethesda
  assets (AGENTS.md "Legal & IP boundary").
- App verification supplements unit tests, probes, benchmarks, and offscreen
  evidence; it does not replace them.
