import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One inventory owner: its identity, which plugin record its baseline comes
/// from, and the cell its mutations are attributed to.
///
/// The three travel together because every mutation needs all three, and
/// passing them separately at each call site is how a mutation ends up
/// attributed to the wrong cell. `cell` is optional for the same reason the
/// store's is: a script may empty a container in a cell that has never been
/// loaded.
nonisolated public struct InventoryHolder: Equatable, Sendable {
    public let key: ReferenceKey
    public let owner: InventoryOwner
    public let cell: CellSceneLocation?

    public init(key: ReferenceKey, owner: InventoryOwner, cell: CellSceneLocation? = nil) {
        self.key = key
        self.owner = owner
        self.cell = cell
    }

    /// The player, whose baseline is empty and who belongs to no cell.
    public static let player = InventoryHolder(key: .player, owner: .player, cell: nil)
}

/// Which plugin record an owner's baseline comes from.
///
/// A `ReferenceKey` alone cannot answer this: the store keys state by identity
/// and knows nothing about record types, so the caller that has the placement
/// says which kind of owner it is holding.
nonisolated public enum InventoryOwner: Equatable, Sendable {
    /// The player, whose baseline is empty.
    case player
    /// A placed CONT, identified by its base record.
    case container(base: FormID)
    /// A placed ACHR, identified by its NPC_ base record.
    case actor(base: FormID)
    /// An owner with no plugin baseline at all — a runtime-created object such
    /// as a dropped-item pile (#177) or a summon.
    case generated
}
