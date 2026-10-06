// Equip and unequip on the player or the nearest NPC. An equip on the NPC
// queues a cell rebuild, so the actor redraws from its new equipped set.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// Equips on `target`, unequipping whatever conflicts. A nil `item` picks
    /// the first equippable stack.
    @discardableResult
    public func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        guard let equipment else { return InventoryCore.noEquipmentText }
        guard let holder = holder(for: target) else {
            return note(InventoryCore.noTargetText(target))
        }
        let state = equipment.inventory.inventory(of: holder)
        guard
            let chosen = item ?? InventoryCore.firstEquippable(
                in: state, occupancy: equipment.occupancy(of:)
            )
        else {
            return note("Nothing equippable held.")
        }
        do {
            let change = try equipment.equip(chosen, on: holder)
            // After the write, so the refresh reads this equip's result.
            world?.equipmentChanged(on: holder)
            return note(InventoryCore.equipSentence(
                changed: change.changed,
                item: name(of: chosen),
                target: label(target),
                unequipped: change.unequipped.map { name(of: $0) }
            ))
        } catch {
            return note("Equip failed: \(String(describing: error))")
        }
    }

    /// Unequips on `target`. A nil `item` picks the first worn item.
    @discardableResult
    public func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        guard let equipment else { return InventoryCore.noEquipmentText }
        guard let holder = holder(for: target) else {
            return note(InventoryCore.noTargetText(target))
        }
        guard let chosen = item ?? equipment.equipped(on: holder).first else {
            return note("\(label(target)) is wearing nothing.")
        }
        let changed = equipment.unequip(chosen, on: holder)
        world?.equipmentChanged(on: holder)
        return note(changed
            ? "Unequipped \(name(of: chosen)) on \(label(target))."
            : "\(name(of: chosen)) was not equipped on \(label(target)).")
    }

    /// What `target` wears. Empty without equipment or without a target.
    public func equippedReadout(on target: EquipmentTargetSelector) -> [EquippedItemReadout] {
        guard let equipment, let holder = holder(for: target) else { return [] }
        return equipment.equipped(on: holder).map { item in
            EquippedItemReadout(
                name: name(of: item),
                occupancy: InventoryCore.describe(equipment.occupancy(of: item)),
                enchantment: world?.enchantmentLine(of: item, on: holder.key)
            )
        }
    }

    /// The nearest resident ACHR as a holder. The readout and the actions
    /// share it, so they agree on which actor "nearest" means.
    public func nearestActorHolder() -> InventoryHolder? {
        guard
            let runtime,
            let entry = world?.nearestActorEntry(),
            let actor = entry.placedActor
        else { return nil }
        return runtime.actorHolder(entry: entry, base: actor.base)
    }

    func holder(for target: EquipmentTargetSelector) -> InventoryHolder? {
        switch target {
        case .player: runtime?.player
        case .nearestActor: nearestActorHolder()
        }
    }

    private func label(_ target: EquipmentTargetSelector) -> String {
        switch target {
        case .player: "the player"
        case .nearestActor: nearestActorHolder().map(InventoryCore.actorName) ?? "no actor"
        }
    }
}
