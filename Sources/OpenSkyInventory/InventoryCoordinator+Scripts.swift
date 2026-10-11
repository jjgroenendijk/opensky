// The item natives a script calls: `AddItem`, `RemoveItem`, `RemoveAllItems`,
// `GetItemCount`, `EquipItem`, `UnequipItem`, and `SetOutfit`. Each one names its holder by
// reference, so the player, a placed actor, and a container all work.
// Rules: docs/engine/inventory-state.md, "Script item natives".

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// `ObjectReference.AddItem`. False without a holder or for a bad count.
    public func scriptAddItem(_ item: FormID, count: Int32, to key: ReferenceKey) -> Bool {
        guard let runtime, let holder = scriptHolder(key), count > 0 else { return false }
        do {
            try runtime.inventory.add(item, count: count, to: holder)
        } catch {
            return false
        }
        scriptNote("Script added \(count) \(name(of: item)) to \(holderName(holder)).")
        return true
    }

    /// `ObjectReference.RemoveItem`: takes up to `count`, never more than held,
    /// and moves the items to `other` when one is named.
    public func scriptRemoveItem(
        _ item: FormID, count: Int32, from key: ReferenceKey, to other: ReferenceKey?
    ) -> Bool {
        guard let runtime, let holder = scriptHolder(key) else { return false }
        let taken = min(count, runtime.inventory.count(of: item, in: holder))
        guard taken > 0 else { return true }
        let changed = move(item, count: taken, from: holder, to: other.flatMap(scriptHolder))
        if changed {
            world?.equipmentChanged(on: holder)
        }
        return changed
    }

    /// `ObjectReference.RemoveAllItems`: empties the holder, worn items too,
    /// into `other` when one is named.
    public func scriptRemoveAllItems(from key: ReferenceKey, to other: ReferenceKey?) -> Bool {
        guard let runtime, let holder = scriptHolder(key) else { return false }
        let destination = other.flatMap(scriptHolder)
        var changed = false
        for stack in runtime.inventory.inventory(of: holder).stacks {
            changed = move(stack.item, count: stack.count, from: holder, to: destination)
                || changed
        }
        world?.equipmentChanged(on: holder)
        scriptNote("Script emptied \(holderName(holder)).")
        return changed
    }

    /// `ObjectReference.GetItemCount`. Nil without a holder.
    public func scriptItemCount(_ item: FormID, in key: ReferenceKey) -> Int32? {
        guard let runtime, let holder = scriptHolder(key) else { return nil }
        return runtime.inventory.count(of: item, in: holder)
    }

    /// `Actor.EquipItem`. An actor that does not hold the item is given one first.
    public func scriptEquipItem(_ item: FormID, on key: ReferenceKey) -> Bool {
        guard let equipment, let holder = scriptHolder(key) else { return false }
        if equipment.inventory.count(of: item, in: holder) == 0 {
            guard (try? equipment.inventory.add(item, count: 1, to: holder)) != nil else {
                return false
            }
        }
        guard (try? equipment.equip(item, on: holder)) != nil else { return false }
        world?.equipmentChanged(on: holder)
        scriptNote("Script equipped \(name(of: item)) on \(holderName(holder)).")
        return true
    }

    /// `Actor.UnequipItem`. Unequipping what is not worn changes nothing.
    public func scriptUnequipItem(_ item: FormID, on key: ReferenceKey) -> Bool {
        guard let equipment, let holder = scriptHolder(key) else { return false }
        if equipment.unequip(item, on: holder) {
            world?.equipmentChanged(on: holder)
        }
        return true
    }

    /// `Actor.SetOutfit`: the default outfit's pieces leave, then the new pieces
    /// are given and worn. Slot rules unequip whatever else the new pieces cover.
    public func scriptSetOutfit(_ outfit: FormID, on key: ReferenceKey) -> Bool {
        guard
            let equipment, let holder = scriptHolder(key),
            let pieces = equipment.inventory.baselines.outfitStacks(outfit)
        else { return false }
        let inventory = equipment.inventory
        let kept = Set(pieces.map(\.item))
        let defaults = inventory.baselines.baseline(for: holder.owner).equipped
        for item in defaults where !kept.contains(item) {
            let held = inventory.count(of: item, in: holder)
            if held > 0 {
                _ = move(item, count: held, from: holder, to: nil)
            }
        }
        for piece in pieces {
            if inventory.count(of: piece.item, in: holder) == 0 {
                guard (try? inventory.add(piece.item, count: 1, to: holder)) != nil else {
                    continue
                }
            }
            _ = try? equipment.equip(piece.item, on: holder)
        }
        world?.equipmentChanged(on: holder)
        scriptNote("Script set the outfit of \(holderName(holder)).")
        return true
    }

    /// The player, a resident actor, or any other resident reference as a container.
    func scriptHolder(_ key: ReferenceKey) -> InventoryHolder? {
        guard key != .player else { return .player }
        guard let runtime, let entry = runtime.references?.referenceEntry(key: key) else {
            return nil
        }
        if let actor = entry.placedActor {
            return runtime.actorHolder(entry: entry, base: actor.base)
        }
        guard let reference = entry.placedReference else { return nil }
        return InventoryHolder(
            key: entry.key,
            owner: .container(base: reference.base),
            cell: runtime.references?.cellLocation(of: entry.key)
        )
    }

    private func move(
        _ item: FormID, count: Int32, from source: InventoryHolder, to destination: InventoryHolder?
    ) -> Bool {
        guard let runtime else { return false }
        do {
            if let destination, destination.key != source.key {
                try runtime.inventory.transfer(item, count: count, from: source, to: destination)
            } else {
                try runtime.inventory.remove(item, count: count, from: source)
            }
            return true
        } catch {
            return false
        }
    }

    private func holderName(_ holder: InventoryHolder) -> String {
        holder.key == .player ? "the player" : InventoryCore.actorName(holder)
    }

    private func scriptNote(_ text: String) {
        _ = note(text)
    }
}
