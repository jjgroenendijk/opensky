// Main-app World verification-surface coverage: the destination that replaced
// the bare Viewport row must actually show its controls and readouts, drive the
// movement mode back into the renderer, and distinguish "no window has closed
// yet" from a genuinely stalled frame.

import AppKit
@testable import opensky
import Testing

/// Records what the Triggers section asks of the live streamer (issue #173).
/// `FakeWorldProviders` forwards its `TriggerControlProviding` conformance
/// here, so a registry-built panel and a directly built one observe the same
/// fake.
@MainActor
final class FakeTriggerProvider {
    var snapshot = TriggerStatsSnapshot.unavailable
    private(set) var clearCount = 0

    func clear() {
        clearCount += 1
        snapshot = TriggerStatsSnapshot(
            streamerAvailable: snapshot.streamerAvailable,
            stats: snapshot.stats,
            occupiedCount: snapshot.occupiedCount,
            walkModeActive: snapshot.walkModeActive,
            recentTransitions: [],
            recordedTransitionCount: 0
        )
    }
}

extension FakeWorldProviders {
    var triggerStatsSnapshot: TriggerStatsSnapshot {
        triggers.snapshot
    }

    func clearTriggerLog() {
        triggers.clear()
    }
}

struct WorldPanelTests {
    @MainActor
    private func makePanel(_ providers: FakeWorldProviders) -> WorldPanelViewController {
        let panel = WorldPanelViewController()
        panel.loadViewIfNeeded()
        panel.cameraProvider = providers
        panel.frameStatsProvider = providers
        panel.sceneStatsProvider = providers
        panel.triggerProvider = providers
        panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
        return panel
    }

    /// A resident trigger set with one dropped source of each kind, so the
    /// readout's silent-truncation counters are all non-zero.
    private func triggerSnapshot(
        occupied: Int, walkMode: Bool, transitions: [String] = [], recorded: Int? = nil
    ) -> TriggerStatsSnapshot {
        var stats = TriggerVolumeStats()
        stats.meshVolumeCount = 8
        stats.primitiveVolumeCount = 4
        stats.excludedPrimitiveCount = 3
        stats.degenerateVolumeCount = 1
        stats.unkeyedReferenceCount = 2
        return TriggerStatsSnapshot(
            streamerAvailable: true,
            stats: stats,
            occupiedCount: occupied,
            walkModeActive: walkMode,
            recentTransitions: transitions,
            recordedTransitionCount: recorded ?? transitions.count
        )
    }

    @Test @MainActor
    func cameraControlsHaveVisibleFramesInsideTheScrollDocument() throws {
        let panel = makePanel(FakeWorldProviders())
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let controls: [NSView] = [
            panel.cameraMovementModeControl,
            panel.cameraCopyPoseControl,
            panel.triggerLogClearControl
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
        #expect(try #require(scrollView.documentView).frame.height > 0)
    }

    /// The fly/walk selector is what makes the `G` key an accelerator rather
    /// than the only way in (docs/tools/app-ui.md).
    @Test @MainActor
    func movementModeControlRoundTripsProviderState() {
        let providers = FakeWorldProviders()
        providers.movementMode = .walk
        let panel = makePanel(providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.cameraMovementModeControl.titleOfSelectedItem == "Walk")

        panel.cameraMovementModeControl.selectItem(withTitle: "Fly")
        let control = panel.cameraMovementModeControl
        control.sendAction(control.action, to: control.target)
        #expect(providers.movementMode == .fly)
        #expect(
            providers.refocusCount == 1,
            "control interaction must hand focus back to the world"
        )
    }

    @Test @MainActor
    func cameraReadoutShowsMovementValuesAndSources() {
        let providers = FakeWorldProviders()
        providers.movementConfiguration = PlayerMovementConfiguration(
            walkSpeed: MovementSetting(value: 100, source: "Skyrim.esm"),
            runSpeed: MovementSetting(value: 370, source: "engine default"),
            stepHeight: MovementSetting(value: 32, source: "OpenSky fallback")
        )
        let panel = makePanel(providers)
        panel.cameraSection.refreshReadout()
        let readout = panel.cameraSection.statsReadout

        #expect(readout.contains("Walk: 100.0 units/s (Skyrim.esm)"))
        #expect(readout.contains("Run: 370.0 units/s (engine default)"))
        #expect(readout.contains("Step: 32.0 units (OpenSky fallback)"))
    }

    @Test @MainActor
    func copyPosePutsTheSharedDescriptionOnThePasteboard() {
        let providers = FakeWorldProviders()
        providers.cameraPose = CameraPoseSnapshot(
            position: SIMD3<Float>(10, 20, 30), yaw: 0, pitch: 0,
            cell: CellCoordinate(x: 1, y: 2), movementMode: .fly
        )
        let panel = makePanel(providers)
        let control = panel.cameraCopyPoseControl
        control.sendAction(control.action, to: control.target)
        #expect(NSPasteboard.general.string(forType: .string) == providers.cameraPoseDescription)
    }

    /// An `.empty` snapshot means no window has closed yet. Rendering its zeros
    /// would claim the renderer is running at zero frames per second.
    @Test @MainActor
    func frameReadoutReportsMeasuringBeforeTheFirstWindowCloses() {
        let providers = FakeWorldProviders()
        let panel = makePanel(providers)
        panel.frameSection.refreshReadout()
        #expect(panel.frameSection.statsReadout == "Frame: measuring")

        providers.frameStatsSnapshot = FrameStatsSnapshot(
            fps: 60, frameMS: 16.7, maxFrameMS: 20, encodeMS: 4, gpuMS: nil, sampleCount: 30
        )
        panel.frameSection.refreshReadout()
        #expect(panel.frameSection.statsReadout.contains("FPS: 60"))
        // A GPU average is nil until a counter-heap pair resolves.
        #expect(panel.frameSection.statsReadout.contains("GPU: n/a"))
    }

    @Test @MainActor
    func sceneReadoutShowsDrawAndResidencyNumbers() {
        let providers = FakeWorldProviders()
        providers.sceneStatsSnapshot = SceneStatsSnapshot(
            drawCalls: 12, drawnInstances: 340, culledInstances: 56,
            residentCellCount: 9, memoryFootprintMB: 1234.5
        )
        let panel = makePanel(providers)
        panel.sceneSection.refreshReadout()
        let readout = panel.sceneSection.statsReadout
        #expect(readout.contains("Draw calls: 12"))
        #expect(readout.contains("Drawn: 340"))
        #expect(readout.contains("Resident cells: 9"))
        #expect(readout.contains("Memory: 1234 MB"))
    }

    /// The accessibility ids are the UI-test contract, pinned here because the
    /// UI-test harness does not run on every machine (docs/tools/environment.md).
    @Test @MainActor
    func triggerSectionPublishesItsAccessibilityIdentifiers() {
        let panel = makePanel(FakeWorldProviders())
        #expect(panel.triggerSection.sectionIdentifier == "triggerVolumes")
        #expect(panel.triggerLogClearControl.accessibilityIdentifier() == "TriggerLogClearControl")
        let labels = panel.triggerSection.view.subviews
            .compactMap { $0.accessibilityIdentifier() }
        #expect(labels.contains("TriggerVolumeStatsLabel"))
    }

    /// Without a streamer there is nothing to count, and a row of zeros would
    /// read as "no cell authors a trigger".
    @Test @MainActor
    func triggerReadoutReportsAnAbsentStreamer() {
        let panel = makePanel(FakeWorldProviders())
        panel.triggerSection.refreshReadout()
        #expect(panel.triggerSection.statsReadout == "Trigger volumes: unavailable")
    }

    @Test @MainActor
    func triggerReadoutShowsAuthoringSourcesDroppedCountsAndWalkGate() {
        let providers = FakeWorldProviders()
        providers.triggers.snapshot = triggerSnapshot(occupied: 1, walkMode: true)
        let panel = makePanel(providers)
        panel.triggerSection.refreshReadout()
        let readout = panel.triggerSection.statsReadout

        #expect(readout.contains("Volumes: 12 resident  Occupied: 1"))
        #expect(readout.contains("Sources: mesh 8  primitive 4"))
        #expect(readout.contains("Dropped: excluded 3  degenerate 1  unkeyed 2"))
        #expect(readout.contains("Occupancy: walk mode, live"))
    }

    /// Leaving walk mode freezes occupancy instead of clearing it, so the
    /// readout has to name the gate — otherwise a stale non-zero count in fly
    /// mode reads as a bug (docs/engine/collision-world.md).
    @Test @MainActor
    func triggerReadoutNamesFrozenOccupancyOutsideWalkMode() {
        let providers = FakeWorldProviders()
        providers.triggers.snapshot = triggerSnapshot(occupied: 2, walkMode: false)
        let panel = makePanel(providers)
        panel.triggerSection.refreshReadout()
        #expect(panel.triggerSection.statsReadout.contains("Occupancy: fly mode, frozen at 2"))

        providers.triggers.snapshot = triggerSnapshot(occupied: 0, walkMode: false)
        panel.triggerSection.refreshReadout()
        #expect(panel.triggerSection.statsReadout.contains("Occupancy: fly mode, not tested"))
    }

    @Test @MainActor
    func triggerTransitionLogRendersItsTailAndTheClearControlEmptiesIt() {
        let providers = FakeWorldProviders()
        providers.triggers.snapshot = triggerSnapshot(
            occupied: 1,
            walkMode: true,
            transitions: ["enter skyrim.esm:0ABCDE 0x000ABCDE", "leave skyrim.esm:0ABCDE unloaded"],
            recorded: 5
        )
        let panel = makePanel(providers)
        panel.triggerSection.refreshReadout()
        let readout = panel.triggerSection.eventsReadout
        #expect(readout.contains("enter skyrim.esm:0ABCDE 0x000ABCDE"))
        #expect(readout.contains("leave skyrim.esm:0ABCDE unloaded"))
        // Three of the five recorded transitions fell off the bounded ring.
        #expect(readout.contains("3 older dropped"))

        let control = panel.triggerLogClearControl
        control.sendAction(control.action, to: control.target)
        #expect(providers.triggers.clearCount == 1)
        #expect(panel.triggerSection.eventsReadout == "No transitions recorded.")
        #expect(providers.refocusCount == 1, "clearing must hand focus back to the world")
    }
}
