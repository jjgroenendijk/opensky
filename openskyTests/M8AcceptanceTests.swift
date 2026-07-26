// M8 milestone acceptance (issue #150). Drives the whole gate flow — select
// World, enter walk mode, inspect the live HUD, pause, change a setting while
// paused, resume — through the real shell types: the destination registry, the
// sidebar view controller, the registry's own panel factories, and the panel
// controls a user clicks. Nothing here is a second mocking layer: the only
// stand-in is `FakeWorldProviders` (shared with the other panel tests), which
// is the same provider surface the game controller implements, and its
// menu-mode state runs on the real `MenuModeController`.
//
// `make test-ui` is blocked on the development machine (TCC harness init), so
// this unit-level test is the deterministic evidence for the gate. Readouts are
// read back by accessibility identifier out of the built view hierarchy, which
// also pins those identifiers as the UI-test contract. No game data and no
// rendered frames are involved; see docs/tools/sidebar-acceptance.md.

import AppKit
@testable import opensky
import simd
import Testing

/// One M8 acceptance session: the provider set the panels bind to, the real
/// sidebar, and the registry factories that build each destination's panel.
@MainActor
private final class M8AcceptanceHarness {
    let providers = FakeWorldProviders()
    let sidebar = AppSidebarViewController()

    /// Last destination the sidebar reported through the shell's own callback.
    private(set) var selectedDestinationID: String?

    var context: WorldPanelContext {
        WorldPanelContext(providers: providers)
    }

    init() {
        sidebar.onSelect = { [weak self] descriptor in
            self?.selectedDestinationID = descriptor.id
        }
        sidebar.isDestinationOverridden = { [weak self] id in
            guard let self else { return false }
            return DestinationRegistry.destination(id: id)?
                .overrides?.isOverridden(context) ?? false
        }
        _ = sidebar.view
    }

    /// Selects the sidebar row and builds that destination's panel through the
    /// registry factory, exactly as the shell does on selection.
    func select(_ id: String) -> (any InspectorPanel)? {
        sidebar.select(id: id)
        guard
            case let .worldInspector(makePanel) = DestinationRegistry.destination(id: id)?.content
        else { return nil }
        let panel = makePanel(context)
        panel.loadViewIfNeeded()
        refresh(panel)
        return panel
    }

    /// Runs one inspection pass (sync controls, refresh readouts) without
    /// leaving the 2 Hz ticker running, so assertions stay deterministic.
    func refresh(_ panel: any InspectorPanel) {
        panel.startInspecting()
        panel.stopInspecting()
    }

    func overrideIndicatorIsVisible(_ id: String) -> Bool? {
        sidebar.refreshOverrideIndicators()
        return sidebar.overrideIndicatorIsVisible(destinationID: id)
    }

    /// Text of the readout label carrying `identifier`, found in the built
    /// panel; nil when no such label is on screen.
    func readout(_ identifier: String, in panel: any InspectorPanel) -> String? {
        Self.label(identifier, in: panel.view)
    }

    private static func label(_ identifier: String, in view: NSView) -> String? {
        if view.accessibilityIdentifier() == identifier, let field = view as? NSTextField {
            return field.stringValue
        }
        for subview in view.subviews {
            if let found = label(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}

@MainActor
private func send(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

struct M8AcceptanceTests {
    // MARK: Step 1 — select World

    /// The launch destination resolves, reports itself through the sidebar's
    /// selection callback, and builds the World inspector with a live camera
    /// readout.
    @Test @MainActor
    func selectingWorldBuildsTheLaunchInspector() throws {
        let harness = M8AcceptanceHarness()
        let descriptor = try #require(DestinationRegistry.destination(id: "world"))
        #expect(descriptor.sidebarIdentifier == "Destination-world")
        #expect(DestinationRegistry.defaultDestinationID == "world")

        harness.providers.cameraPose = CameraPoseSnapshot(
            position: SIMD3<Float>(10, 20, 30), yaw: 0, pitch: 0,
            cell: CellCoordinate(x: 1, y: 2), movementMode: .fly
        )
        let panel = try #require(harness.select("world") as? WorldPanelViewController)
        #expect(harness.selectedDestinationID == "world")

        let camera = try #require(harness.readout("CameraStatsLabel", in: panel))
        #expect(camera.contains("Position: 10.0, 20.0, 30.0"))
        #expect(camera.contains("Cell: 1, 2"))
    }

    // MARK: Step 2 — enter walk mode

    /// Walk mode is settable from the sidebar (the `G` key is only an
    /// accelerator), the provider takes it, and the sidebar row's override dot
    /// reports the non-default state.
    @Test @MainActor
    func enteringWalkModeTakesAndShowsAsAnOverride() throws {
        let harness = M8AcceptanceHarness()
        let panel = try #require(harness.select("world") as? WorldPanelViewController)
        #expect(harness.overrideIndicatorIsVisible("world") == false)

        panel.cameraMovementModeControl.selectItem(withTitle: "Walk")
        send(panel.cameraMovementModeControl)

        #expect(harness.providers.movementMode == .walk)
        harness.refresh(panel)
        #expect(panel.cameraMovementModeControl.titleOfSelectedItem == "Walk")
        #expect(harness.overrideIndicatorIsVisible("world") == true)
        #expect(harness.readout("CameraStatsLabel", in: panel)?.isEmpty == false)
    }

    // MARK: Step 3 — inspect and toggle the live HUD

    /// The HUD destination toggles the live vanilla-SWF layer and reports both
    /// the element state and the current interaction target.
    @Test @MainActor
    func hudDestinationTogglesElementsAndReportsTheLiveTarget() throws {
        let harness = M8AcceptanceHarness()
        harness.providers.hudControlSnapshot = Self.liveHUDSnapshot
        let panel = try #require(
            harness.select("hudInteraction") as? HUDInteractionPanelViewController
        )
        #expect(harness.overrideIndicatorIsVisible("hudInteraction") == false)

        let elements = panel.elementsSection
        elements.crosshairControl.state = .off
        send(elements.crosshairControl)
        #expect(!harness.providers.hudCrosshairEnabled)

        elements.layerControl.state = .off
        send(elements.layerControl)
        #expect(!harness.providers.hudLayerEnabled)
        #expect(harness.overrideIndicatorIsVisible("hudInteraction") == true)

        harness.refresh(panel)
        let elementsReadout = try #require(harness.readout("HUDElementsStatsLabel", in: panel))
        #expect(elementsReadout.contains("HUD: loaded"))
        #expect(elementsReadout.contains("Draw calls: 12"))
        let target = try #require(harness.readout("HUDTargetStatsLabel", in: panel))
        #expect(target.contains("Prompt: Open Test Door"))
        #expect(target.contains("Action: Open Test Door"))
    }

    // MARK: Steps 4-6 — pause, change a setting, resume

    /// Pushing a menu from the UI Lab pauses world sim on the real
    /// `MenuModeController`, an Environment setting still applies while paused,
    /// popping the menu resumes, and the setting survives the resume.
    @Test @MainActor
    func menuModePausesWorldSimWhileASettingStillApplies() throws {
        let harness = M8AcceptanceHarness()
        let uiLab = try #require(harness.select("uiLab") as? UILabPanelViewController)
        let running = try Self.menuReadout(harness, uiLab)
        #expect(running.contains("World sim: running"))

        send(uiLab.menuPushControl)
        harness.refresh(uiLab)
        let paused = try Self.menuReadout(harness, uiLab)
        #expect(paused.contains("World sim: paused"))
        #expect(paused.contains("Menu mode: on"))
        #expect(paused.contains("Depth: 1"))

        try Self.changeShadowQualityWhilePaused(harness)

        send(uiLab.menuPopControl)
        harness.refresh(uiLab)
        let resumed = try Self.menuReadout(harness, uiLab)
        #expect(resumed.contains("World sim: running"))
        #expect(resumed.contains("Depth: 0"))
        // The setting changed while paused is durable across the resume.
        #expect(harness.providers.shadowQuality == .low)
        #expect(!harness.providers.sunShadowsEnabled)
    }

    /// The system menu is the second, gameplay-facing pause surface: opening it
    /// pauses world sim and Resume clears it.
    @Test @MainActor
    func systemMenuPausesAndResumesWorldSim() throws {
        let harness = M8AcceptanceHarness()
        let panel = try #require(harness.select("systemMenu") as? SystemMenuPanelViewController)
        let closed = try #require(harness.readout("SystemMenuStatsLabel", in: panel))
        #expect(closed.contains("world sim running"))

        send(panel.menuSection.openControl)
        harness.refresh(panel)
        #expect(harness.providers.systemMenuSnapshot.worldSimPaused)
        let open = try #require(harness.readout("SystemMenuStatsLabel", in: panel))
        #expect(open.contains("world sim paused"))

        send(panel.menuSection.resumeControl)
        harness.refresh(panel)
        #expect(!harness.providers.systemMenuIsOpen)
        let resumed = try #require(harness.readout("SystemMenuStatsLabel", in: panel))
        #expect(resumed.contains("world sim running"))
    }

    // MARK: The gate — one uninterrupted session

    /// The M8 gate in one session, in the order a user performs it, with a
    /// single provider set carried across every destination: World, walk mode,
    /// HUD & Interaction, pause, a setting change while paused, resume.
    @Test @MainActor
    func acceptanceFlowRunsEndToEndWithoutTheCLI() throws {
        let harness = M8AcceptanceHarness()
        harness.providers.hudControlSnapshot = Self.liveHUDSnapshot

        let world = try #require(harness.select("world") as? WorldPanelViewController)
        #expect(harness.selectedDestinationID == "world")
        world.cameraMovementModeControl.selectItem(withTitle: "Walk")
        send(world.cameraMovementModeControl)
        #expect(harness.providers.movementMode == .walk)

        let hud = try #require(
            harness.select("hudInteraction") as? HUDInteractionPanelViewController
        )
        #expect(harness.selectedDestinationID == "hudInteraction")
        hud.elementsSection.crosshairControl.state = .off
        send(hud.elementsSection.crosshairControl)
        harness.refresh(hud)
        #expect(!harness.providers.hudCrosshairEnabled)
        let target = try #require(harness.readout("HUDTargetStatsLabel", in: hud))
        #expect(target.contains("Open Test Door"))

        let uiLab = try #require(harness.select("uiLab") as? UILabPanelViewController)
        send(uiLab.menuPushControl)
        harness.refresh(uiLab)
        let paused = try Self.menuReadout(harness, uiLab)
        #expect(paused.contains("World sim: paused"))

        try Self.changeShadowQualityWhilePaused(harness)
        #expect(harness.providers.menuModeSnapshot.isWorldSimPaused, "still paused")

        send(uiLab.menuPopControl)
        harness.refresh(uiLab)
        let resumed = try Self.menuReadout(harness, uiLab)
        #expect(resumed.contains("World sim: running"))
        // Walk mode and the HUD override outlive the pause, so the sidebar
        // still marks both destinations as overridden after the resume.
        #expect(harness.overrideIndicatorIsVisible("world") == true)
        #expect(harness.overrideIndicatorIsVisible("hudInteraction") == true)
    }

    // MARK: Shared steps

    /// Changes an Environment setting through its sidebar control and checks it
    /// applied and reached the readout. Called while world sim is paused.
    @MainActor
    private static func changeShadowQualityWhilePaused(_ harness: M8AcceptanceHarness) throws {
        let panel = try #require(harness.select("environment") as? EnvironmentPanelViewController)
        panel.sunShadowsEnabledControl.state = .off
        send(panel.sunShadowsEnabledControl)
        #expect(!harness.providers.sunShadowsEnabled)

        panel.shadowSection.qualityControl.selectItem(withTitle: "Low")
        send(panel.shadowSection.qualityControl)
        #expect(harness.providers.shadowQuality == .low)

        harness.refresh(panel)
        let readout = try #require(harness.readout("ShadowStatsLabel", in: panel))
        #expect(readout.contains("Shadows: Low"))
        #expect(harness.overrideIndicatorIsVisible("environment") == true)
    }

    @MainActor
    private static func menuReadout(
        _ harness: M8AcceptanceHarness, _ panel: UILabPanelViewController
    ) throws -> String {
        try #require(harness.readout("UIMenuStatsLabel", in: panel))
    }

    /// A synthetic live-HUD frame: what the engine publishes while walk mode
    /// looks at an activatable door. No game data is involved.
    private static let liveHUDSnapshot = HUDControlSnapshot(
        isLoaded: true,
        loadError: nil,
        targetReference: FormID(0x123),
        targetBase: FormID(0x456),
        targetName: "Test Door",
        targetAction: "Open",
        targetDistance: 87.5,
        targetPosition: SIMD3<Float>(10, 20, 30),
        hitPosition: SIMD3<Float>(11, 21, 31),
        prompt: "Open Test Door",
        markerHeadings: [315],
        cameraHeading: 270,
        scale: 1,
        drawStats: SWFDrawStats(drawCalls: 12)
    )
}
