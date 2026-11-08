import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One container-menu transaction, named by its direction.
nonisolated public enum ContainerTransfer: Equatable, Sendable {
    /// Container to player, marked as theft when the container is owned.
    case take
    /// Player to container.
    case store
    /// Merchant to player, for gold.
    case buy
    /// Player to merchant, for gold.
    case sell
}
