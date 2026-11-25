public import OpenSkyWorldInterface

/// The counts, readouts, and path queries of `CellStreamer` that the agent and the
/// navigation read, apart from the parts that change the world.
public protocol CellStreamerReadoutsPort: AnyObject {
    associatedtype CellAnimatedVehicle: CellAnimatedVehiclePort
    associatedtype CellGridManager: CellGridManagerPort
    var fullLODReferenceCount: Int { get }
    var generatedTerrainBlockCount: Int { get }
    var grid: CellGridManager { get }
    var hiddenLargeReferenceSegments: Int { get }
    var coverageReadout: CellCoverageReadout { get }
    var inFlightCellCount: Int { get }
    var pendingCompletionCount: Int { get }
    var queuedRequestCount: Int { get }
    func residentAnimatedVehicles() -> [CellAnimatedVehicle]
    var residentReferenceCount: Int { get }
    var cachedAssetCounts: CachedAssetCounts? { get }
    func findPath(_ query: NavigationPathQuery) -> NavigationPathResult
    var largeReferenceCount: Int { get }
}
