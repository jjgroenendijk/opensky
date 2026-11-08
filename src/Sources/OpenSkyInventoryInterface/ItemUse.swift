import OpenSkyFormatsESM
import OpenSkyGameData

/// The action a use of one carried item runs.
nonisolated public enum ItemUse: Equatable, Sendable {
    case applyPoison
    case consume
    case equip
    case unequip
}
