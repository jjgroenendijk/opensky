// Always-on frame HUD coverage: the overlay must read the same snapshots the
// World panel reads, distinguish "no window has closed yet" from a stalled
// renderer, honour the persisted show/hide choice, and cost nothing (no
// scheduled timer) whenever it is not on screen.

import AppKit
@testable import opensky
import Testing

@MainActor
struct FrameHUDTests {
    private func measuredFrame(gpuMS: Double?) -> FrameStatsSnapshot {
        FrameStatsSnapshot(
            fps: 60, frameMS: 16.7, maxFrameMS: 20, encodeMS: 4,
            gpuMS: gpuMS, sampleCount: 30
        )
    }

    private func scene() -> SceneStatsSnapshot {
        SceneStatsSnapshot(
            drawCalls: 12, drawnInstances: 340, culledInstances: 56,
            residentCellCount: 9, memoryFootprintMB: 1234.5
        )
    }

    @Test func formatsEveryNumberTheWorldPanelShows() {
        let text = FrameHUDView.statsText(frame: measuredFrame(gpuMS: 4.2), scene: scene())
        #expect(text.contains("FPS 60"))
        #expect(text.contains("Frame 16.70 ms"))
        #expect(text.contains("GPU 4.20 ms"))
        #expect(text.contains("Draws 12"))
        #expect(text.contains("Drawn 340"))
        #expect(text.contains("Culled 56"))
        #expect(text.contains("Cells 9"))
        #expect(text.contains("Memory 1234 MB"))
    }

    /// The first half second has no closed window; rendering the zeroed
    /// snapshot would read as a renderer that had stopped.
    @Test func emptyFrameSnapshotReadsAsMeasuring() {
        let text = FrameHUDView.statsText(frame: .empty, scene: .empty)
        #expect(text.contains("measuring"))
        #expect(!text.contains("FPS 0"))
    }

    /// The GPU average stays nil until a counter-heap pair resolves, and the
    /// footprint is nil when the mach call fails.
    @Test func missingGPUAndMemoryRenderAsNotAvailable() {
        let noMemory = SceneStatsSnapshot(
            drawCalls: 1, drawnInstances: 2, culledInstances: 3,
            residentCellCount: 4, memoryFootprintMB: nil
        )
        let text = FrameHUDView.statsText(frame: measuredFrame(gpuMS: nil), scene: noMemory)
        #expect(text.contains("GPU n/a"))
        #expect(text.contains("Memory n/a"))
    }

    @Test func readoutTracksTheWiredProviders() {
        let providers = FakeWorldProviders()
        providers.frameStatsSnapshot = measuredFrame(gpuMS: 4.2)
        providers.sceneStatsSnapshot = scene()
        let hud = FrameHUDView()
        hud.wire(providers: providers)
        #expect(hud.statsReadout.contains("FPS 60"))
        #expect(hud.statsReadout.contains("Cells 9"))
    }

    /// The persisted choice decides visibility at construction, and the toggle
    /// both applies and stores it.
    @Test func visibilityFollowsThePersistedChoice() {
        let key = FrameHUDView.visibilityDefaultsKey
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set(false, forKey: key)
        let hidden = FrameHUDView()
        #expect(hidden.isHidden)
        #expect(!hidden.isTicking)

        UserDefaults.standard.set(true, forKey: key)
        let shown = FrameHUDView()
        #expect(!shown.isHidden)

        shown.isEnabled = false
        #expect(shown.isHidden)
        #expect(UserDefaults.standard.bool(forKey: key) == false)
    }

    /// A hidden HUD must cost nothing: no scheduled refresh timer.
    @Test func tickerRunsOnlyWhileTheOverlayIsShown() {
        let key = FrameHUDView.visibilityDefaultsKey
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: key)

        let hud = FrameHUDView()
        hud.resumeUpdates()
        #expect(hud.isTicking)

        hud.isEnabled = false
        #expect(!hud.isTicking)

        hud.isEnabled = true
        #expect(hud.isTicking)

        // Covering the game view stops it too, without touching the choice.
        hud.setGameCovered(true)
        #expect(hud.isHidden)
        #expect(!hud.isTicking)
        #expect(hud.isEnabled)

        hud.setGameCovered(false)
        #expect(!hud.isHidden)
        #expect(hud.isTicking)

        hud.suspendUpdates()
        #expect(!hud.isTicking)
    }
}
