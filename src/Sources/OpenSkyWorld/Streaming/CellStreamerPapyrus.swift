// Script-lifecycle emission. The streamer announces cells joining or leaving the world
// and knows no VM; the app forwards to `PapyrusWorldRuntime`. A scene without a
// `CellSceneLocation` is not announced, because the location is the subscriber's key.

import Foundation
public import OpenSkyCells
public import OpenSkyGameData

extension CellStreamer.TriggerSteps {
    /// Announces a cell that is now part of the live world.
    ///
    /// - Parameter firstIntegration: false when the cell never left and its
    ///   scene was merely rebuilt, which is the signal not to re-fire load
    ///   events.
    public func emitCellAttached(_ scene: CellScene, firstIntegration: Bool) {
        guard let location = scene.location else { return }
        // A queued announcement of the same cell is replaced; scripts never saw it.
        let queuedFirst = takeQueuedAttachment(at: location)?.isFirstIntegration ?? false
        streamer.events.onCellAttached(CellAttachment(
            scene: scene,
            isFirstIntegration: firstIntegration || queuedFirst
        ))
        streamer.events.cellHazards(CellHazardEvent(location: location, hazards: scene.hazards))
    }

    /// Announces a cell that left the world; a nil or unlocated scene is a no-op. Occupied
    /// volumes fire `leave` before the detach, because detach drops queued events. Trigger
    /// release is not gated on the location: a volume always has a `ReferenceKey`.
    public func emitCellDetached(_ scene: CellScene?) {
        guard let scene else { return }
        releaseTriggers(in: scene)
        guard let location = scene.location else { return }
        // A cell that leaves before its first announcement was never in the world.
        if takeQueuedAttachment(at: location)?.isFirstIntegration == true {
            return
        }
        streamer.events.onCellDetached(location)
        streamer.events.cellHazards(CellHazardEvent(location: location, hazards: []))
    }
}

extension CellStreamer.TriggerSteps {
    /// Queues the announcement of a cell that joined in a ring swap. Many cells can join
    /// in one swap, so the scripts take them one per frame, and no frame pays for all.
    func queueCellAttached(_ scene: CellScene, firstIntegration: Bool) {
        guard scene.location != nil else { return }
        streamer.queuedAttachments.append(
            CellAttachment(scene: scene, isFirstIntegration: firstIntegration)
        )
    }

    /// Announces the oldest queued cell, once per frame.
    func emitNextQueuedAttachment() {
        guard !streamer.queuedAttachments.isEmpty else { return }
        let next = streamer.queuedAttachments.removeFirst()
        emitCellAttached(next.scene, firstIntegration: next.isFirstIntegration)
    }

    private func takeQueuedAttachment(at location: CellSceneLocation) -> CellAttachment? {
        guard
            let index = streamer.queuedAttachments.firstIndex(where: {
                $0.scene.location == location
            })
        else { return nil }
        return streamer.queuedAttachments.remove(at: index)
    }
}

/// The enabled hazards of one live cell. An empty list on detach drops them all.
nonisolated public struct CellHazardEvent: Sendable {
    public let location: CellSceneLocation
    public let hazards: [CellHazard]
}
