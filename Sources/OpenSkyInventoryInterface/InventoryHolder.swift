import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One inventory owner: its identity, the plugin record its baseline comes from,
/// and the cell its writes are attributed to. They travel together so a write
/// cannot name the wrong cell. `cell` is optional: a script may change a
/// container in an unloaded cell.
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
    /// An owner with no plugin baseline, such as a dropped-item pile or a summon.
    case generated
}
