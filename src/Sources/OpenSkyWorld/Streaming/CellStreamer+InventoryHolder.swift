// The inventory holder of a resident actor, which equipment and tempering read.

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyWorldState

extension CellStreamer.ResidentSteps {
    /// The player's own holder, or a resident actor's; nil for anything else.
    public func inventoryHolder(of key: ReferenceKey) -> InventoryHolder? {
        if key == .player {
            return .player
        }
        guard let actor = referenceEntry(key: key)?.placedActor else { return nil }
        return .resident(key, base: actor.base, cell: cellLocation(of: key))
    }
}

extension InventoryHolder {
    /// A resident actor's holder: it owns what its base record gives it.
    static func resident(
        _ key: ReferenceKey, base: FormID, cell: CellSceneLocation?
    ) -> InventoryHolder {
        InventoryHolder(key: key, owner: .actor(base: base), cell: cell)
    }
}
