// Read-only streaming counters for verification, benchmarks, and tests. Split
// out of CellStreamer.swift for the strict file-length limit; the properties
// are unchanged.

import Foundation
import OpenSkyCells
public import OpenSkyFormatsCore
import OpenSkyTerrain

extension CellStreamer.CoverageSteps {
    /// Grid slots that reached a terminal state: resident + void + failed.
    public var resolvedCellCount: Int {
        streamer.core.resident.count + streamer.core.void.count + streamer.core.failed.count
    }

    public var residentCellCount: Int {
        streamer.core.resident.count
    }

    public var residentCoordinates: Set<CellCoordinate> {
        streamer.core.resident
    }

    public var voidCellCount: Int {
        streamer.core.void.count
    }

    public var failedCellCount: Int {
        streamer.core.failed.count
    }

    public var inFlightCellCount: Int {
        streamer.core.inFlight.count
    }

    public var pendingCompletionCount: Int {
        streamer.pending.count
    }

    public var queuedRequestCount: Int {
        streamer.requests.count
    }

    /// The full grid the manager currently wants around its center.
    public var desiredCellCount: Int {
        streamer.grid.desiredCells.count
    }

    var distantLODBlockCount: Int {
        streamer.composition.distantLOD?.blockCount ?? 0
    }

    /// Large references past the loaded grid drawn with their full model.
    var largeReferenceCount: Int {
        streamer.composition.distantLOD?.largeReferenceCount ?? 0
    }

    /// Is Full LOD references the distant ring draws with their full model.
    var fullLODReferenceCount: Int {
        streamer.composition.distantLOD?.fullLODReferenceCount ?? 0
    }

    /// Terrain blocks the ring draws from the generated LOD.
    var generatedTerrainBlockCount: Int {
        streamer.composition.distantLOD?.generatedTerrainBlockCount ?? 0
    }

    /// Cell segments of object LOD large-reference shapes hidden for the ring.
    var hiddenLargeReferenceSegments: Int {
        streamer.composition.distantLOD?.hiddenLargeReferenceSegments ?? 0
    }

    public var composedCellCount: Int {
        streamer.composition.cellCount
    }

    public var isInterior: Bool {
        streamer.interiorScene != nil
    }
}
