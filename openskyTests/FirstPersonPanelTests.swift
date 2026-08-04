// The `World > First person` verification surface (issue #190): the controls
// exist, are laid out, drive the provider, and the readout says what the frame
// alone cannot — whether the graph loaded, how many arm meshes survived the
// MOD4/MOD5 projection, and which pieces were dropped for declaring none.
//
// The accessibility ids asserted here are the UI-test API. `make test-ui` is
// TCC-blocked on this machine (docs/tools/environment.md), so they are pinned
// as literal assertions.

import AppKit
@testable import opensky
import Testing

struct FirstPersonPanelTests {
    @MainActor
    private func makePanel(_ providers: FakeWorldProviders) -> WorldPanelViewController {
        let panel = WorldPanelViewController()
        panel.loadViewIfNeeded()
        panel.cameraProvider = providers
        panel.firstPersonProvider = providers
        panel.frameStatsProvider = providers
        panel.sceneStatsProvider = providers
        panel.triggerProvider = providers
        panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
        return panel
    }

    private func snapshot(
        active: Bool = true,
        graphAttached: Bool = true,
        rigAttached: Bool = true,
        failureReason: String? = nil,
        armModelCount: Int = 3,
        droppedPieceCount: Int = 2,
        hasCameraBone: Bool = true,
        missingVariables: [String] = [],
        missingEvents: [String] = []
    ) -> FirstPersonSnapshot {
        FirstPersonSnapshot(
            rendererAvailable: true,
            active: active,
            graphAttached: graphAttached,
            rigAttached: rigAttached,
            failureReason: failureReason,
            armModelCount: armModelCount,
            droppedPieceCount: droppedPieceCount,
            hasCameraBone: hasCameraBone,
            cameraBoneHeight: hasCameraBone ? 121 : nil,
            graphUpdates: 240,
            missingVariables: missingVariables,
            missingEvents: missingEvents,
            fovYDegrees: FirstPersonCamera.defaultFOVYDegrees
        )
    }

    // MARK: - Layout and ids

    @Test @MainActor
    func firstPersonControlsAreLaidOutInsideTheScrollDocument() throws {
        let panel = makePanel(FakeWorldProviders())
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 900)
        panel.view.layoutSubtreeIfNeeded()

        let controls: [NSView] = [
            panel.firstPersonArmsEnabledControl,
            panel.firstPersonFOVControl
        ]
        for control in controls {
            let name = control.accessibilityIdentifier()
            #expect(!control.isHidden, "\(name) hidden")
            #expect(control.frame.height > 0, "\(name) frame=\(control.frame)")
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(
                scrollView.documentView?.bounds.intersects(documentFrame) == true,
                "\(name) outside document: \(documentFrame)"
            )
        }
    }

    @Test @MainActor
    func accessibilityIdsAreTheOnesTheUITestsUse() {
        let panel = makePanel(FakeWorldProviders())
        panel.view.layoutSubtreeIfNeeded()
        #expect(
            panel.firstPersonArmsEnabledControl.accessibilityIdentifier()
                == "FirstPersonArmsEnabledControl"
        )
        #expect(panel.firstPersonFOVControl.accessibilityIdentifier() == "FirstPersonFOVControl")
        #expect(panel.firstPersonSection.sectionIdentifier == "first-person")
    }

    // MARK: - Controls

    @Test @MainActor
    func armsToggleRoundTripsProviderState() {
        let providers = FakeWorldProviders()
        let panel = makePanel(providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let control = panel.firstPersonArmsEnabledControl
        #expect(control.state == .on)
        control.state = .off
        control.sendAction(control.action, to: control.target)
        #expect(!providers.firstPersonArmsEnabled)
        #expect(providers.refocusCount == 1)
    }

    @Test @MainActor
    func fieldOfViewControlWritesDegreesThrough() {
        let providers = FakeWorldProviders()
        let panel = makePanel(providers)
        panel.view.layoutSubtreeIfNeeded()
        let control = panel.firstPersonFOVControl
        #expect(control.minValue == Double(MatrixMath.degrees(
            fromRadians: FirstPersonCamera.fovYRange.lowerBound
        )))
        #expect(control.maxValue == Double(MatrixMath.degrees(
            fromRadians: FirstPersonCamera.fovYRange.upperBound
        )))
        control.floatValue = 90
        control.sendAction(control.action, to: control.target)
        #expect(providers.firstPersonFOVYDegrees == 90)
    }

    /// The override indicator and Reset all have to see a changed field of
    /// view, or a session drifts from the defaults with nothing saying so.
    @Test @MainActor
    func overrideAndResetCoverBothControls() {
        let providers = FakeWorldProviders()
        #expect(!FirstPersonSection.isOverridden(provider: providers))
        providers.firstPersonFOVYDegrees = 90
        #expect(FirstPersonSection.isOverridden(provider: providers))
        FirstPersonSection.resetToDefaults(provider: providers)
        #expect(providers.firstPersonFOVYDegrees == FirstPersonCamera.defaultFOVYDegrees)

        providers.firstPersonArmsEnabled = false
        #expect(FirstPersonSection.isOverridden(provider: providers))
        FirstPersonSection.resetToDefaults(provider: providers)
        #expect(providers.firstPersonArmsEnabled)
        #expect(!FirstPersonSection.isOverridden(provider: providers))
    }

    // MARK: - Readout

    @Test @MainActor
    func readoutReportsTheRigTheGraphAndTheDroppedPieces() {
        let providers = FakeWorldProviders()
        providers.firstPerson.snapshot = snapshot()
        let panel = makePanel(providers)
        panel.firstPersonSection.refreshReadout()
        let readout = panel.firstPersonSection.statsReadout

        #expect(readout.contains("Arms: drawn"))
        #expect(readout.contains("Graph: attached"))
        #expect(readout.contains("updates: 240"))
        #expect(readout.contains("meshes: 3"))
        #expect(readout.contains("dropped: 2"))
        #expect(readout.contains("Camera1st [Cam1] at z 121.0"))
        #expect(readout.contains("Field of view: 65 deg"))
    }

    /// A missing `_1stperson` set has to say so in words. "No arms" and "arms
    /// behind you" look identical in a frame.
    @Test @MainActor
    func readoutNamesWhyThereAreNoArms() {
        let providers = FakeWorldProviders()
        providers.firstPerson.snapshot = snapshot(
            active: false,
            graphAttached: false,
            rigAttached: false,
            failureReason: "behavior asset missing: _1stperson\\behaviors\\0_master.hkx",
            armModelCount: 0,
            droppedPieceCount: 0,
            hasCameraBone: false
        )
        let panel = makePanel(providers)
        panel.firstPersonSection.refreshReadout()
        let readout = panel.firstPersonSection.statsReadout

        #expect(readout.contains("Arms: not drawn"))
        #expect(readout.contains("Graph: none"))
        #expect(readout.contains("Rig: none"))
        #expect(readout.contains("No arms: behavior asset missing"))
        #expect(readout.contains("Camera bone: absent"))
    }

    /// A name the `_1stperson` set spells differently is a named miss rather
    /// than motion that quietly does nothing.
    @Test @MainActor
    func readoutNamesUnboundVariablesAndEvents() {
        let providers = FakeWorldProviders()
        providers.firstPerson.snapshot = snapshot(
            missingVariables: ["SpeedRun"], missingEvents: ["SwimStart"]
        )
        let panel = makePanel(providers)
        panel.firstPersonSection.refreshReadout()
        let readout = panel.firstPersonSection.statsReadout
        #expect(readout.contains("Unbound variables: SpeedRun"))
        #expect(readout.contains("Unbound events: SwimStart"))
    }

    @Test @MainActor
    func readoutReportsNoRendererRatherThanZeros() {
        let providers = FakeWorldProviders()
        providers.firstPerson.snapshot = .unavailable
        let panel = makePanel(providers)
        panel.firstPersonSection.refreshReadout()
        #expect(panel.firstPersonSection.statsReadout == "First person: no renderer")
    }
}
