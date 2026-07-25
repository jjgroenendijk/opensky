// Main-app World verification-surface coverage: the destination that replaced
// the bare Viewport row must actually show its controls and readouts, drive the
// movement mode back into the renderer, and distinguish "no window has closed
// yet" from a genuinely stalled frame.

import AppKit
@testable import opensky
import Testing

struct WorldPanelTests {
    @MainActor
    private func makePanel(_ providers: FakeWorldProviders) -> WorldPanelViewController {
        let panel = WorldPanelViewController()
        panel.loadViewIfNeeded()
        panel.cameraProvider = providers
        panel.frameStatsProvider = providers
        panel.sceneStatsProvider = providers
        panel.refocusAction = { [weak providers] in providers?.refocusGameView() }
        return panel
    }

    @Test @MainActor
    func cameraControlsHaveVisibleFramesInsideTheScrollDocument() throws {
        let panel = makePanel(FakeWorldProviders())
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        panel.view.layoutSubtreeIfNeeded()

        let controls: [NSView] = [panel.cameraMovementModeControl, panel.cameraCopyPoseControl]
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
}
