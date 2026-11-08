public import OpenSkyFormatsCore

/// What the world adapters use of `CellGridManager`.
public protocol CellGridManagerPort {
    var center: CellCoordinate { get }
}
