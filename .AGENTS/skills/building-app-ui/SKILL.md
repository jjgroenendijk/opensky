---
name: building-app-ui
description: Adds or changes OpenSky main-app UI - sidebar destinations, control panels, and
  inspectors, covering where a control goes, the destination registry, how a panel reads a
  coordinator through a ControlProviding seam, the panel base classes and shared components,
  and the accessibility-id contract. Use before any app-shell UI work.
---

# Main-app UI

This is the app's own dev and verification UI: sidebar destinations and the control panels
under them. It is not the in-game Scaleform UI.

| Part | Where it lives |
| --- | --- |
| Shell, registry, panel base classes, components | `Sources/OpenSky/Shell/` |
| One section (one control group) | `Sources/OpenSky/Shell/Sections/` |
| One view controller per destination | `Sources/OpenSky/Panels/` |
| The game view and its one-line panel forwards | `Sources/OpenSky/GameView/` |
| The logic a panel drives | A coordinator in the feature module (`docs/engine/coordinators.md`) |

The full reference is `docs/tools/app-ui.md`. This skill holds the decisions and points at
the section of that page with each detail.

## Workflow

1. Decide where the surface goes.
2. Give the panel a seam to read: the feature's `XControlProviding` protocol.
3. Build the section from the shared components.
4. Register a new destination, if step 1 asked for one.
5. Pin the accessibility ids and test the panel.

## 1. Where a new surface goes

Decide before building, because the number of settings grows without end:

1. A new knob for an existing subsystem -> add it to that subsystem's section.
2. A new, separate subsystem -> a new section under the destination that owns it.
3. A new destination only for full-height or full-content space, a separate surface named
   as a top-level path, or a section that has outgrown its destination (about 8 controls,
   or it needs its own navigation). Details: "Placement" in `docs/tools/app-ui.md`.

Parser, math, and infrastructure-only work may wait for its first visible consumer. If its
output is useful alone, expose it in the Asset Browser or an inspector.

## 2. The seam a panel reads

A panel never holds game logic, and it never reads `GameViewController` directly. The data
flows like this, with the crime panel as the example:

1. The logic lives in a coordinator in the feature module: `CrimeCoordinator` in
   `Sources/OpenSkyCrime/`. Test it there with `make test-unit`.
2. The panel's seam is a protocol in the same module: `CrimeFactionControlProviding`, with
   snapshot value types for the readout. A seam that another feature also reads goes in the
   feature's `Interface` module. A seam that names several features goes in
   `OpenSkyMenus/` (`Sources/AGENTS.md`, Folder layout).
3. `GameViewController` conforms with one-line forwards to the coordinator, in
   `GameView/GameViewControllerPanels.swift`. A seam with many members gets a
   `...ControlForwarding` protocol beside it whose extension does the forwarding, such as
   `AudioControlForwarding`; the view controller then conforms in one line.
4. Add the protocol to `WorldControlProviders` in `Shell/DestinationRegistry.swift`.
5. The destination's factory assigns `context.providers` to the section's provider
   property.

Do not add a `GameViewController+X.swift` file, and do not put rules in a section or a
panel. A rule there can only be tested by building the app.

## 3. Build the section

Subclass `PanelSectionViewController` for one control group and
`InspectorPanelViewController` for a destination panel. Model files:

- `Shell/Sections/AudioFootstepsSection.swift`: one section with a provider, controls, and
  a readout.
- `Panels/ScriptsPanelViewController.swift`: a thin panel that composes sections.
- `Tests/OpenSkyTests/App/Panels/AudioFootstepsPanelTests.swift`: its tests.

Build controls only from `PanelComponents` and `PanelMetrics`. If a widget is missing, add
it there instead of hand-rolling one in a section. `InspectionTicker` owns the 2 Hz
readout; do not add a timer. The base-class hooks, the component table, and the spacing
scale are in "Building panels" in `docs/tools/app-ui.md`.

Panels exist to check that a feature works, so a user should try it without reading first:

- No paragraphs in a panel. Explain a control in one plain sentence as its `toolTip`. A
  design reason goes in a code comment or `docs/`, not in the UI.
- A readout line is a label and a value, such as `Hits: 1 of 2 swings`. Not a sentence, not
  an instruction, not a record code such as `CRIF` or `AVIF`. An empty state is short:
  `Target: none`.
- Use the words a player knows: "swings", not "contact frames".

`make panel-text` fails on a wrapping label built from text and on a tooltip over 100
characters. Details: "Panel text" in `docs/tools/app-ui.md`.

These invariants are each pinned by a unit test. Break one -> fix the code, not the test.
The reasons are in "Layout invariants" and "Interaction rules" in `docs/tools/app-ui.md`.

- A collapsed section takes only its header height. `CollapsibleSectionView` keeps header
  and content as arranged subviews of an `NSStackView`, because Auto Layout reclaims a
  hidden view's space only when it is arranged.
- Never pin a `heightAnchor` constant on a section control. A fixed height defeats
  intrinsic sizing and survives hiding.
- No dev behavior is reachable only by an unadvertised keystroke. Every toggle is a panel
  control. A shortcut is allowed only as an accelerator for an existing control, registered
  in the main menu so it is listed. Camera and gameplay input is input, not configuration.
- Panels are built on first reveal and cached by destination id, never all at launch.

## 4. Register a destination

- Add one `DestinationDescriptor` to `DestinationRegistry.all`. Never edit the shell view
  controllers to add a destination; the registry is the only registration point. The
  sidebar sections are `world`, `developer`, and `library`, in that order.
- A `worldInspector` factory wires the panel's providers from `context.providers`. A
  `fullContent` factory gets a `FullContentContext`, and its controller conforms to
  `FullContentReloadable` so a Settings reload reaches the cached instance.
- A mutable destination registers `DestinationOverrideActions` beside its descriptor. The
  sidebar indicator and Reset all use them and never build an unopened panel. Details:
  "Override provenance and reset" in `docs/tools/app-ui.md`.
- AppKit code goes under `Sources/OpenSky/`, which only the app builds. `make cli-boundary`
  fails if it lands in a package module.

## 5. Accessibility ids and verification

Ids are the UI-test API, so never change one silently. The patterns: `AppSidebar` outline,
`Destination-<id>` rows, `PanelSection-<id>` headers, `<Thing>Control` and
`<Thing>StatsLabel`, `PanelSection-<id>-OverrideIndicator` and
`PanelSection-<id>-ResetControl`, `Destination-<id>-OverrideIndicator`, the menu item
`ResetAllOverridesCommand`, and the toolbar `ScreenshotButton`.

- Pin new ids as literals in the panel test, and destination ids in
  `DestinationRegistryTests`. Update the literals in the same change that renames an id.
- Keep `OpenSkyUITests` correct even where the UI-test harness cannot run locally
  (`docs/tools/environment.md`).
- Run the panel tests and the coordinator tests with `make test-unit T='...'`, then
  `make verify-build`, because only it compiles the app (`testing-and-verifying` skill).
- Update `docs/tools/app-ui.md` in the same commit when the framework changes.
- At milestone acceptance, write the record from `docs/tools/sidebar-acceptance.md` into
  the PR that closes the milestone, not into `docs/`. The tests are the evidence; any A/B
  capture stays in gitignored `logs/`.
