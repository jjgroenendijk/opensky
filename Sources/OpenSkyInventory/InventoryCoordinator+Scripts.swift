// The item natives a script calls: `AddItem`, `RemoveItem`, `RemoveAllItems`,
// `GetItemCount`, `EquipItem`, `UnequipItem`, `SetOutfit`, and the equipment reads. Each one names
// its holder by
// reference, so the player, a placed actor, and a container all work.
// Rules: docs/engine/inventory-state.md, "Script item natives".

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
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
    ) -> InventoryResult<Bool> {
        guard let runtime, let holder = scriptHolder(key) else { return InventoryResult(false) }
        let taken = min(count, runtime.inventory.count(of: item, in: holder))
        guard taken > 0 else { return InventoryResult(true) }
        let changed = move(item, count: taken, from: holder, to: other.flatMap(scriptHolder))
        return InventoryResult(changed, commands: changed ? [.equipmentChanged(holder)] : [])
    }

    /// `ObjectReference.DropObject`: up to `count` land in front of the player as one
    /// stack. Only the player drops, because only the player has a drop placement.
    /// - Returns: the dropped reference, or nil when nothing was dropped.
    public func scriptDropObject(
        _ item: FormID, count: Int32, from key: ReferenceKey
    ) -> InventoryResult<ReferenceKey?> {
        guard key == .player, let runtime, let placement = world.dropPlacement() else {
            return InventoryResult(nil)
        }
        let dropped = min(count, runtime.inventory.count(of: item, in: runtime.player))
        guard dropped > 0, let spawned = try? runtime.drop(item, count: dropped, at: placement)
        else { return InventoryResult(nil) }
        storyEvents?.reportStoryEvent(.removeItem(item, reference: nil, owner: nil, how: .dropped))
        scriptNote("Script dropped \(dropped) \(name(of: item)).")
        return InventoryResult(spawned, commands: [.equipmentChanged(runtime.player)])
    }

    /// `ObjectReference.RemoveAllItems`: empties the holder, worn items too,
    /// into `other` when one is named.
    public func scriptRemoveAllItems(
        from key: ReferenceKey, to other: ReferenceKey?
    ) -> InventoryResult<Bool> {
        guard let runtime, let holder = scriptHolder(key) else { return InventoryResult(false) }
        let destination = other.flatMap(scriptHolder)
        var changed = false
        for stack in runtime.inventory.inventory(of: holder).stacks {
            changed = move(stack.item, count: stack.count, from: holder, to: destination)
                || changed
        }
        scriptNote("Script emptied \(holderName(holder)).")
        return InventoryResult(changed, commands: [.equipmentChanged(holder)])
    }

    /// `ObjectReference.GetItemCount`. Nil without a holder.
    public func scriptItemCount(_ item: FormID, in key: ReferenceKey) -> Int32? {
        guard let runtime, let holder = scriptHolder(key) else { return nil }
        return runtime.inventory.count(of: item, in: holder)
    }

    /// `Actor.EquipItem`. An actor that does not hold the item is given one first.
    public func scriptEquipItem(_ item: FormID, on key: ReferenceKey) -> InventoryResult<Bool> {
        guard let equipment, let holder = scriptHolder(key) else { return InventoryResult(false) }
        if equipment.inventory.count(of: item, in: holder) == 0 {
            guard (try? equipment.inventory.add(item, count: 1, to: holder)) != nil else {
                return InventoryResult(false)
            }
        }
        guard (try? equipment.equip(item, on: holder)) != nil else { return InventoryResult(false) }
        scriptNote("Script equipped \(name(of: item)) on \(holderName(holder)).")
        return InventoryResult(true, commands: [.equipmentChanged(holder)])
    }

    /// `Form.GetGoldValue`: the item's `DATA` value. Nil for a form that is no item.
    public func scriptGoldValue(of item: FormID) -> Int32? {
        runtime?.inventory.baselines.items.definition(item)?.value
    }

    /// `Actor.IsEquipped`. Nil without a holder.
    public func scriptIsEquipped(_ item: FormID, on key: ReferenceKey) -> Bool? {
        guard let equipment, let holder = scriptHolder(key) else { return nil }
        return equipment.isEquipped(item, on: holder)
    }

    /// `Actor.GetEquippedWeapon(abLeftHand)`. A two-handed weapon is in the right hand.
    /// The outer nil means no holder; the inner nil means an empty hand.
    public func scriptEquippedWeapon(on key: ReferenceKey, leftHand: Bool) -> FormID?? {
        guard let equipment, let holder = scriptHolder(key) else { return nil }
        return .some(equipment.equipped(on: holder).first { item in
            guard
                let equippable = equipment.catalog.item(item),
                equippable.animationType != nil
            else { return false }
            let hands = equippable.occupancy.hands
            return leftHand ? hands == .leftHand : hands.contains(.rightHand)
        })
    }

    /// `Actor.GetEquippedShield`: the worn armour in biped slot 39.
    public func scriptEquippedShield(on key: ReferenceKey) -> FormID?? {
        guard let equipment, let holder = scriptHolder(key) else { return nil }
        return .some(equipment.equipped(on: holder).first {
            equipment.occupancy(of: $0).slots.contains(.shield)
        })
    }

    /// `Actor.UnequipAll`. The items stay in the inventory.
    public func scriptUnequipAll(on key: ReferenceKey) -> InventoryResult<Bool> {
        guard let equipment, let holder = scriptHolder(key) else { return InventoryResult(false) }
        let changed = equipment.unequipAll(on: holder)
        return InventoryResult(true, commands: changed ? [.equipmentChanged(holder)] : [])
    }

    /// `Actor.UnequipItem`. Unequipping what is not worn changes nothing.
    public func scriptUnequipItem(_ item: FormID, on key: ReferenceKey) -> InventoryResult<Bool> {
        guard let equipment, let holder = scriptHolder(key) else { return InventoryResult(false) }
        let changed = equipment.unequip(item, on: holder)
        return InventoryResult(true, commands: changed ? [.equipmentChanged(holder)] : [])
    }

    /// `Actor.UnequipItemSlot(aiSlot)`: takes off every worn item that covers biped slot
    /// `aiSlot`, 30 to 61. The items stay in the inventory.
    public func scriptUnequipSlot(_ slot: Int32, on key: ReferenceKey) -> InventoryResult<Bool> {
        guard (30 ... 61).contains(slot), let equipment, let holder = scriptHolder(key) else {
            return InventoryResult(false)
        }
        let mask = BodySlots(rawValue: 1 << UInt32(slot - 30))
        let worn = equipment.equipped(on: holder).filter {
            !equipment.occupancy(of: $0).slots.isDisjoint(with: mask)
        }
        for item in worn {
            _ = equipment.unequip(item, on: holder)
        }
        return InventoryResult(true, commands: worn.isEmpty ? [] : [.equipmentChanged(holder)])
    }

    /// `Actor.SetOutfit`: the default outfit's pieces leave, then the new pieces
    /// are given and worn. Slot rules unequip whatever else the new pieces cover.
    public func scriptSetOutfit(_ outfit: FormID, on key: ReferenceKey) -> InventoryResult<Bool> {
        guard
            let equipment, let holder = scriptHolder(key),
            let pieces = equipment.inventory.baselines.outfitStacks(outfit)
        else { return InventoryResult(false) }
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
        scriptNote("Script set the outfit of \(holderName(holder)).")
        return InventoryResult(true, commands: [.equipmentChanged(holder)])
    }

    /// The plugin inventory of a resident holder, for a diff against its first write.
    public func scriptBaselineInventory(of key: ReferenceKey) -> ReferenceInventoryState? {
        guard let runtime, let holder = scriptHolder(key) else { return nil }
        return runtime.inventory.baselines.baseline(for: holder.owner)
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
        _ = note(.script(text))
    }
}
