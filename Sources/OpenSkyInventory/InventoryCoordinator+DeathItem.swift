// The death item: an actor's `INAM` list goes into its inventory when it dies,
// rolled at the actor's own level. See docs/engine/leveled-lists.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

extension InventoryCoordinator {
    /// Gives the actor at `key` its death item. The roll is seeded by the reference,
    /// so two corpses of one base can differ.
    /// - Returns: the stacks added; empty when there was nothing to add.
    @discardableResult
    public func grantDeathItem(to key: ReferenceKey, actorLevel: Int) -> [InventoryStack] {
        guard
            let runtime, let holder = scriptHolder(key),
            case let .actor(base) = holder.owner
        else { return [] }
        let stacks = runtime.inventory.baselines.deathItemStacks(
            for: base, roll: runtime.inventory.roll(of: holder), level: actorLevel
        )
        guard
            !stacks.isEmpty, (try? runtime.inventory.apply(
                removing: [], adding: stacks, on: holder
            )) != nil else { return [] }
        return stacks
    }
}
