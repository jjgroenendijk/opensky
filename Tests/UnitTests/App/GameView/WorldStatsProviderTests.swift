// The camera / frame-stats / scene-stats seams the World panel and the frame
// HUD both read. A GameViewController whose view was never loaded has no
// renderer and no streamer — the same state a machine without Metal 4 ends up
// in — so it pins the documented nil-renderer defaults without a GPU.

import AppKit
@testable import opensky
import Testing

@MainActor
struct WorldStatsProviderTests {
    @Test
    func cameraPoseFallsBackToUnavailableWithoutARenderer() {
        let controller = GameViewController()
        #expect(controller.cameraPose == CameraPoseSnapshot.unavailable)
        #expect(controller.movementMode == .fly)
    }

    @Test
    func movementModeWriteIsHarmlessWithoutARenderer() {
        let controller = GameViewController()
        controller.movementMode = .walk
        // No renderer to hold the change; the getter keeps reporting the
        // default rather than a value the engine never adopted.
        #expect(controller.movementMode == .fly)
    }

    @Test
    func cameraPoseDescriptionIsFormattedForABugReport() {
        let controller = GameViewController()
        let description = controller.cameraPoseDescription
        #expect(description.contains("camera fly"))
        #expect(description.contains("position 0.0, 0.0, 0.0"))
        #expect(description.contains("cell 0, 0"))
    }

    /// The protocol extension is the single formatter; a snapshot-driven fake
    /// must produce the same string shape as the live controller.
    @Test
    func cameraPoseDescriptionReadsTheSnapshotItIsGiven() {
        let provider = StubCameraProvider()
        provider.cameraPose = CameraPoseSnapshot(
            position: SIMD3<Float>(4096, -8192, 512),
            yaw: .pi / 2,
            pitch: 0,
            cell: CellCoordinate(x: 1, y: -2),
            movementMode: .walk
        )
        let description = provider.cameraPoseDescription
        #expect(description.contains("camera walk"))
        #expect(description.contains("position 4096.0, -8192.0, 512.0"))
        #expect(description.contains("yaw 90.0 deg"))
        #expect(description.contains("cell 1, -2"))
    }

    @Test
    func frameStatsSnapshotIsEmptyWithoutARenderer() {
        let controller = GameViewController()
        #expect(controller.frameStatsSnapshot == FrameStatsSnapshot.empty)
    }

    @Test
    func sceneStatsZeroOutWithoutARendererOrStreamer() {
        let controller = GameViewController()
        let stats = controller.sceneStatsSnapshot
        #expect(stats.drawCalls == 0)
        #expect(stats.drawnInstances == 0)
        #expect(stats.culledInstances == 0)
        #expect(stats.residentCellCount == 0)
        // Footprint is a process reading, so it stays available regardless.
        #expect((stats.memoryFootprintMB ?? 0) > 0)
    }
}

@MainActor
private final class StubCameraProvider: CameraControlProviding {
    var cameraPose = CameraPoseSnapshot.unavailable
    var movementMode = CameraMovementMode.fly
}
