// Read-only streaming counters for verification, benchmarks, and tests. Split
// out of CellStreamer.swift for the strict file-length limit; the properties
// are unchanged.

import Foundation

extension CellStreamer {
    /// Grid slots that reached a terminal state: resident + void + failed.
    var resolvedCellCount: Int {
        core.resident.count + core.void.count + core.failed.count
    }

    var residentCellCount: Int {
        core.resident.count
    }

    var residentCoordinates: Set<CellCoordinate> {
        core.resident
    }

    var voidCellCount: Int {
        core.void.count
    }

    var failedCellCount: Int {
        core.failed.count
    }

    var inFlightCellCount: Int {
        core.inFlight.count
    }

    var pendingCompletionCount: Int {
        pending.count
    }

    var queuedRequestCount: Int {
        requests.count
    }

    /// The full grid the manager currently wants around its center.
    var desiredCellCount: Int {
        grid.desiredCells.count
    }

    /// Snapshot of the currently composed multi-cell scene.
    var composedScene: RenderScene {
        composition.composedScene()
    }

    var distantLODBlockCount: Int {
        composition.distantLOD?.blockCount ?? 0
    }

    var composedCellCount: Int {
        composition.cellCount
    }

    var isCoverageTransitionActive: Bool {
        coverageTransitionActive
    }

    var isInterior: Bool {
        interiorScene != nil
    }

    var residentCollisionStats: StaticCollisionStats {
        if let interiorScene {
            return interiorScene.staticCollision.stats
        }
        return composition.collisionStats()
    }
}
