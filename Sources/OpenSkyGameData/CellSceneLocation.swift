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
