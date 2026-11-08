// The inventory holder of a resident actor, which equipment and tempering read.

public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
import OpenSkyWorldState

extension CellStreamer {
    /// The player's own holder, or a resident actor's; nil for anything else.
    public func inventoryHolder(of key: ReferenceKey) -> InventoryHolder? {
        if key == .player {
            return .player
        }
        guard let actor = referenceEntry(key: key)?.placedActor else { return nil }
        return InventoryHolder(
            key: key,
            owner: .actor(base: actor.base),
            cell: cellLocation(of: key)
        )
    }
}
