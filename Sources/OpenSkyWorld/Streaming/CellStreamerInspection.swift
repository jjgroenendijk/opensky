// Read-only streaming counters for verification, benchmarks, and tests. Split
// out of CellStreamer.swift for the strict file-length limit; the properties
// are unchanged.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyTerrain

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

    public var distantLODBlockCount: Int {
        composition.distantLOD?.blockCount ?? 0
    }

    /// Large references past the loaded grid drawn with their full model.
    public var largeReferenceCount: Int {
        composition.distantLOD?.largeReferenceCount ?? 0
    }

    /// Is Full LOD references the distant ring draws with their full model.
    public var fullLODReferenceCount: Int {
        composition.distantLOD?.fullLODReferenceCount ?? 0
    }

    /// Terrain blocks the ring draws from the generated LOD.
    public var generatedTerrainBlockCount: Int {
        composition.distantLOD?.generatedTerrainBlockCount ?? 0
    }

    /// Cell segments of object LOD large-reference shapes hidden for the ring.
    public var hiddenLargeReferenceSegments: Int {
        composition.distantLOD?.hiddenLargeReferenceSegments ?? 0
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
}
