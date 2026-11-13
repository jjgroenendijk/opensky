// The order the streamer builds cells in, and its memory report per recompose.

import Foundation
import OpenSkyCells
import OpenSkyDiagnostics
import OpenSkyFormatsCore
import OpenSkyTerrain

extension CellStreamer.CoverageSteps {
    /// One-line memory report per recompose -- the streaming footprint budget
    /// is measured, not guessed (docs/engine/cell-streaming.md memory budget).
    func logFootprint() {
        guard let megabytes = MemoryFootprint.physFootprintMB() else { return }
        let residentCount = residentCellCount
        let voidCount = voidCellCount
        let inFlightCount = inFlightCellCount
        CellStreamer.logger.info(
            """
            [INFO] stream: \(residentCount, privacy: .public) resident, \
            \(voidCount, privacy: .public) void, \
            \(inFlightCount, privacy: .public) in flight, \
            footprint \(Int(megabytes), privacy: .public) MB
            """
        )
    }

    /// Dispatches center-out so the launch cell (and nearest neighbors) build
    /// first -- the first integrated cell is the one that frames the camera.
    /// Deterministic tie-break by coordinate keeps dispatch order stable.
    func requestsNearestFirst(_ requests: [CellCoordinate]) -> [CellCoordinate] {
        let center = streamer.grid.center
        return requests.sorted { lhs, rhs in
            let lhsDistance = Self.squaredDistance(lhs, center)
            let rhsDistance = Self.squaredDistance(rhs, center)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return (lhs.x, lhs.y) < (rhs.x, rhs.y)
        }
    }

    private static func squaredDistance(_ lhs: CellCoordinate, _ rhs: CellCoordinate) -> Int {
        let deltaX = Int(lhs.x) - Int(rhs.x)
        let deltaY = Int(lhs.y) - Int(rhs.y)
        return deltaX * deltaX + deltaY * deltaY
    }
}
