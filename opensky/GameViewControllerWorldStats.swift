// Renderer bridge for the World camera + frame/scene readouts. Same shape as
// the other provider extensions: read and write the live renderer on the main
// thread (the context draw(in:) runs in), and degrade to documented defaults
// when there is no renderer (Metal 4 unavailable) or no streamer (missing game
// data, synthetic DemoScene).

import AppKit

extension GameViewController: CameraControlProviding {
    var cameraPose: CameraPoseSnapshot {
        guard let renderer else { return .unavailable }
        let camera = renderer.freeFlyCamera
        return CameraPoseSnapshot(
            position: camera.position,
            yaw: camera.yaw,
            pitch: camera.pitch,
            cell: CellGridManager.cellCoordinate(for: camera.position),
            movementMode: renderer.movementMode
        )
    }

    var movementMode: CameraMovementMode {
        get { renderer?.movementMode ?? .fly }
        set { renderer?.movementMode = newValue }
    }

    var movementConfiguration: PlayerMovementConfiguration {
        renderer?.walkController.configuration ?? .synthetic
    }
}

extension GameViewController: FrameStatsProviding {
    var frameStatsSnapshot: FrameStatsSnapshot {
        renderer?.frameStats.snapshot() ?? .empty
    }
}

/// Trigger-volume accounting and occupancy (issue #173). Without a streamer
/// there is nothing to count, and the snapshot says so instead of reporting
/// zeros that would read as "no cell authors a trigger".
extension GameViewController: TriggerControlProviding {
    var triggerStatsSnapshot: TriggerStatsSnapshot {
        guard let streamer else { return .unavailable }
        return TriggerStatsSnapshot(
            streamerAvailable: true,
            stats: streamer.triggerStats(),
            occupiedCount: streamer.occupiedTriggers.count,
            // Read off the renderer, the same gate
            // `GameViewControllerStreaming.playerCapsule(of:)` tests.
            walkModeActive: renderer?.movementMode == .walk,
            recentTransitions: streamer.triggerLog.lines,
            recordedTransitionCount: streamer.triggerLog.recordedCount
        )
    }

    func clearTriggerLog() {
        streamer?.triggerLog.clear()
    }
}

extension GameViewController: SceneStatsProviding {
    var sceneStatsSnapshot: SceneStatsSnapshot {
        let draw = renderer?.lastDrawStats ?? SceneDrawStats()
        return SceneStatsSnapshot(
            drawCalls: draw.drawCalls,
            drawnInstances: draw.drawnInstances,
            culledInstances: draw.culledInstances,
            residentCellCount: streamer?.residentCellCount ?? 0,
            // Process-wide, so it stays meaningful even with no renderer.
            memoryFootprintMB: MemoryFootprint.physFootprintMB()
        )
    }
}
