// Read-only streaming counters for verification, benchmarks, and tests. Split
// out of CellStreamer.swift for the strict file-length limit; the properties
// are unchanged.

import Foundation
import OpenSkyFormatsCore

extension CellStreamer {
    /// Grid slots that reached a terminal state: resident + void + failed.
    public var resolvedCellCount: Int {
        core.resident.count + core.void.count + core.failed.count
    }

    public var residentCellCount: Int {
        core.resident.count
    }

    public var residentCoordinates: Set<CellCoordinate> {
        core.resident
    }

    public var voidCellCount: Int {
        core.void.count
    }

    public var failedCellCount: Int {
        core.failed.count
    }

    public var inFlightCellCount: Int {
        core.inFlight.count
    }

    public var pendingCompletionCount: Int {
        pending.count
    }

    public var queuedRequestCount: Int {
        requests.count
    }

    /// The full grid the manager currently wants around its center.
    public var desiredCellCount: Int {
        grid.desiredCells.count
    }

    /// Snapshot of the currently composed multi-cell scene.
    public var composedScene: RenderScene {
        composition.composedScene()
    }

    public var distantLODBlockCount: Int {
        composition.distantLOD?.blockCount ?? 0
    }

    public var composedCellCount: Int {
        composition.cellCount
    }

    public var isCoverageTransitionActive: Bool {
        coverageTransitionActive
    }

    public var isInterior: Bool {
        interiorScene != nil
    }

    public var residentCollisionStats: StaticCollisionStats {
        if let interiorScene {
            return interiorScene.staticCollision.stats
        }
        return composition.collisionStats()
    }
}
