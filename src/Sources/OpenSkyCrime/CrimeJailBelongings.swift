// The player's belongings across a jail stay: into the faction's chest at the arrest,
// and back at release.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension CrimeSessionWorld {
    /// Every stack the player carries but one `kept` goes into `chest`.
    func storeBelongings(in chest: ReferenceKey, keeping kept: FormID?) {
        moveAll(from: .player, to: chestHolder(chest), keeping: kept)
    }

    /// The jail outfit goes, and the belongings come back from their chest.
    func returnBelongings(of stay: JailStay) {
        guard let inventory else { return }
        for piece in stay.outfit where inventory.count(of: piece, in: .player) > 0 {
            _ = attempt { try inventory.remove(piece, count: 1, from: .player) }
        }
        if let belongings = stay.belongings {
            moveAll(from: chestHolder(belongings), to: .player, keeping: nil)
        }
    }

    /// Every stack but one of `kept` moves; a failed move leaves the stack where it is.
    private func moveAll(
        from source: InventoryHolder,
        to target: InventoryHolder,
        keeping kept: FormID?
    ) {
        guard let inventory else { return }
        var keptOne = false
        for stack in inventory.inventory(of: source).stacks {
            var count = stack.count
            if stack.item == kept, !keptOne {
                keptOne = true
                count -= 1
            }
            guard
                count > 0,
                attempt({ try inventory.remove(stack.item, count: count, from: source) }) != nil
            else { continue }
            _ = attempt { try inventory.add(stack.item, count: count, to: target) }
        }
    }

    /// The resident chest when it is streamed in, so its own `CNTO` baseline
    /// is kept, and a baseline-free holder under the same key otherwise. Every
    /// `STOL` and `PLCN` chest in `Skyrim.esm` authors no `CNTO`.
    func chestHolder(_ key: ReferenceKey) -> InventoryHolder {
        if let placed = references?.referenceEntry(key: key)?.placedReference {
            return InventoryHolder(
                key: key,
                owner: .container(base: placed.base),
                cell: references?.cellLocation(of: key)
            )
        }
        return InventoryHolder(key: key, owner: .generated)
    }
}
