// M8 acceptance: select World, enter walk mode, read the HUD, pause, change a
// setting while paused, and resume, through the real sidebar, registry, and
// panel controls. `FakeWorldProviders` is the only stand-in; its menu mode runs
// on the real `MenuModeController`. See docs/tools/sidebar-acceptance.md.

import AppKit
@testable import OpenSky
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyMenus
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import TagsTesting
import Testing

@MainActor
private func send(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

@Suite(.tags(.acceptance))
struct WalkModeAcceptanceTests {
    // MARK: Step 1 — select World

    /// The launch destination resolves, reports itself through the sidebar's
    /// selection callback, and builds the World inspector with a live camera
    /// readout.
    @Test @MainActor
    func selectingWorldBuildsTheLaunchInspector() throws {
        let harness = SidebarAcceptanceHarness()
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
        let harness = SidebarAcceptanceHarness()
        let panel = try #require(harness.select("world") as? WorldPanelViewController)
        #expect(harness.overrideIndicatorIsVisible("world") == false)

        panel.cameraMovementModeControl.selectItem(withTitle: "Walk (first person)")
        send(panel.cameraMovementModeControl)

        #expect(harness.providers.movementMode == .walk)
        harness.refresh(panel)
        #expect(panel.cameraMovementModeControl.titleOfSelectedItem == "Walk (first person)")
        #expect(harness.overrideIndicatorIsVisible("world") == true)
        #expect(harness.readout("CameraStatsLabel", in: panel)?.isEmpty == false)
    }

    // MARK: Step 3 — inspect and toggle the live HUD

    /// The HUD destination toggles the live vanilla-SWF layer and reports both
    /// the element state and the current interaction target.
    @Test @MainActor
    func hudDestinationTogglesElementsAndReportsTheLiveTarget() throws {
        let harness = SidebarAcceptanceHarness()
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
        let harness = SidebarAcceptanceHarness()
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
        let harness = SidebarAcceptanceHarness()
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
        let harness = SidebarAcceptanceHarness()
        harness.providers.hudControlSnapshot = Self.liveHUDSnapshot

        let world = try #require(harness.select("world") as? WorldPanelViewController)
        #expect(harness.selectedDestinationID == "world")
        world.cameraMovementModeControl.selectItem(withTitle: "Walk (first person)")
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
    private static func changeShadowQualityWhilePaused(_ harness: SidebarAcceptanceHarness) throws {
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
        _ harness: SidebarAcceptanceHarness, _ panel: UILabPanelViewController
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
