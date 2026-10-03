// Script-lifecycle emission. The streamer announces cells joining or leaving the world
// and knows no VM; the app forwards to `PapyrusWorldRuntime`. A scene without a
// `CellSceneLocation` is not announced, because the location is the subscriber's key.

import Foundation
import OpenSkyGameData

extension CellStreamer {
    /// Announces a cell that is now part of the live world.
    ///
    /// - Parameter firstIntegration: false when the cell never left and its
    ///   scene was merely rebuilt, which is the signal not to re-fire load
    ///   events.
    public func emitCellAttached(_ scene: CellScene, firstIntegration: Bool) {
        guard let location = scene.location else { return }
        onCellAttached?(scene, firstIntegration)
        cellHazards(CellHazardEvent(location: location, hazards: scene.hazards))
    }

    /// Announces a cell that left the world; a nil or unlocated scene is a no-op. Occupied
    /// volumes fire `leave` before the detach, because detach drops queued events. Trigger
    /// release is not gated on the location: a volume always has a `ReferenceKey`.
    public func emitCellDetached(_ scene: CellScene?) {
        guard let scene else { return }
        releaseTriggers(in: scene)
        guard let location = scene.location else { return }
        onCellDetached?(location)
        cellHazards(CellHazardEvent(location: location, hazards: []))
    }
}

/// The enabled hazards of one live cell. An empty list on detach drops them all.
nonisolated public struct CellHazardEvent: Sendable {
    public let location: CellSceneLocation
    public let hazards: [CellHazard]
}
