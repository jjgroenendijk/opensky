import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// Stable identity of one built cell. Exterior cells drive grid streaming;
/// interior cells are addressed by CELL FormID because they have no XCLC.
///
/// `Hashable` because runtime state that outlives a cell — `WorldStateStore`'s
/// per-cell dirty counts — keys dictionaries by the cell a mutation happened
/// in, long after that cell was evicted.
nonisolated public enum CellSceneLocation: Hashable, Sendable {
    case exterior(CellCoordinate)
    case interior(FormID)
}

nonisolated extension CellSceneLocation {
    /// A total order over cell identities, so a dictionary of resident cells
    /// can be visited reproducibly. Exteriors sort by grid coordinate and come
    /// before every interior, which sorts by CELL FormID.
    public static func isOrderedBefore(_ lhs: CellSceneLocation, _ rhs: CellSceneLocation) -> Bool {
        switch (lhs, rhs) {
        case let (.exterior(left), .exterior(right)):
            (left.x, left.y) < (right.x, right.y)
        case let (.interior(left), .interior(right)):
            left.rawValue < right.rawValue
        case (.exterior, .interior):
            true
        case (.interior, .exterior):
            false
        }
    }
}
