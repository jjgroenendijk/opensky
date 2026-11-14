public import OpenSkyFormatsCore

/// Which exterior cells draw in full detail and which wait for their distant ring,
/// for `state frame` (docs/engine/cell-streaming.md, "Distant LOD and coverage").
nonisolated public struct CellCoverageReadout: Equatable, Sendable {
    /// The grid's center cell.
    public var center: CellCoordinate
    /// The cells the grid wants.
    public var wantedCells: Set<CellCoordinate>
    /// The full cells on screen.
    public var drawnCells: Set<CellCoordinate>
    /// Built cells that wait off screen for a ring that leaves them out.
    public var waitingCells: Set<CellCoordinate>
    /// The center of the ring on screen; nil when no ring draws.
    public var ringCenter: CellCoordinate?
    /// A ring is being built.
    public var ringBuilding: Bool
    /// Rings swapped in since the session started.
    public var ringSwaps: Int

    public init(
        center: CellCoordinate, wantedCells: Set<CellCoordinate>, drawnCells: Set<CellCoordinate>,
        waitingCells: Set<CellCoordinate>, ringCenter: CellCoordinate?, ringBuilding: Bool,
        ringSwaps: Int
    ) {
        self.center = center
        self.wantedCells = wantedCells
        self.drawnCells = drawnCells
        self.waitingCells = waitingCells
        self.ringCenter = ringCenter
        self.ringBuilding = ringBuilding
        self.ringSwaps = ringSwaps
    }

    /// The fewest rings from `cell` to a wanted cell that is not drawn; nil when every
    /// wanted cell draws. 1 means a neighbour of `cell` shows LOD.
    public func nearestMissing(from cell: CellCoordinate) -> Int? {
        wantedCells.subtracting(drawnCells).map { other in
            Int(max(abs(Int64(other.x) - Int64(cell.x)), abs(Int64(other.y) - Int64(cell.y))))
        }.min()
    }
}
