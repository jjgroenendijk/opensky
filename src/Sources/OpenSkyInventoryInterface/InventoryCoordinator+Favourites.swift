import OpenSkyFormatsESM
import OpenSkyWorldState

/// What a favourite or hotkey action did, for the readout.
nonisolated public enum FavouriteOutcome: Error, Equatable, Sendable {
    case unavailable
    case marked(String)
    case unmarked(String)
    case bound(String, slot: Int)
    case badSlot(Int)
    case emptySlot(Int)
    case notCarried(String)
}
