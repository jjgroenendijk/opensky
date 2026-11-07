// A commanded follower takes an item or empties a container or body. A take from an
// owner is theft by the player, who gave the order (UESP "Skyrim:Followers", Morality).
// See docs/engine/follower-commands.md.

import OpenSkyCrimeInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// Moves every stack `key` holds to `follower`, marked stolen when the take is theft.
    /// True when anything moved.
    public func followerTakeAll(
        from key: ReferenceKey, by follower: ReferenceKey
    ) -> InventoryResult<Bool> {
        guard
            let runtime, let source = scriptHolder(key), let destination = scriptHolder(follower)
        else { return InventoryResult(false) }
        // Looting a body is no theft.
        let isBody = if case .actor = source.owner {
            true
        } else {
            false
        }
        var moved = false
        for stack in runtime.inventory.inventory(of: source).stacks {
            let verdict: OwnershipVerdict = isBody
                ? .unowned : runtime.crime?.verdict(on: key, item: stack.item) ?? .unowned
            let transferred: Void? = attempt {
                try runtime.inventory.transfer(
                    stack.item, count: stack.count, from: source, to: destination,
                    markingStolen: verdict.isTheft
                )
            }
            guard transferred != nil else { continue }
            moved = true
            if verdict.isTheft {
                runtime.crime?.reportTheft(
                    of: stack.item, count: stack.count, from: key, owner: verdict.owner
                )
            }
        }
        return InventoryResult(moved, commands: moved ? [.equipmentChanged(source)] : [])
    }

    /// Moves a loose item into `follower`'s inventory and out of the world.
    public func followerPickUp(_ item: ReferenceKey, by follower: ReferenceKey) -> Bool {
        guard
            let runtime, let destination = scriptHolder(follower),
            let entry = runtime.references?.referenceEntry(key: item),
            let reference = entry.placedReference
        else { return false }
        let count = max(1, reference.itemCount ?? 1)
        let verdict = runtime.crime?.verdict(on: item, item: reference.base) ?? .unowned
        do {
            try runtime.inventory.add(
                reference.base, count: count, to: destination, stolen: verdict.isTheft
            )
        } catch {
            return false
        }
        if verdict.isTheft {
            runtime.crime?.reportTheft(
                of: reference.base, count: count, from: item, owner: verdict.owner
            )
        }
        runtime.removeFromWorld(item, cell: runtime.references?.cellLocation(of: item))
        return true
    }
}
