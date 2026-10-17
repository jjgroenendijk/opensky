// Equip and unequip on the player or the nearest NPC. An equip on the NPC
// queues a cell rebuild, so the actor redraws from its new equipped set.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// Equips on `target`, unequipping whatever conflicts. A nil `item` picks
    /// the first equippable stack.
    public func equipItem(
        _ item: FormID?, on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome> {
        guard let equipment else { return InventoryResult(.noEquipment) }
        guard let holder = holder(for: target) else {
            return InventoryResult(note(.noEquipTarget(target)))
        }
        let state = equipment.inventory.inventory(of: holder)
        guard
            let chosen = item ?? InventoryCore.firstEquippable(
                in: state, occupancy: equipment.occupancy(of:)
            )
        else { return InventoryResult(note(.nothingEquippable)) }
        do {
            let change = try equipment.equip(chosen, on: holder)
            let outcome = note(.equipped(
                item: name(of: chosen),
                target: label(target),
                changed: change.changed,
                unequipped: change.unequipped.map { name(of: $0) }
            ))
            return InventoryResult(outcome, commands: [.equipmentChanged(holder)])
        } catch {
            return InventoryResult(note(.failed(
                action: "Equip",
                reason: String(describing: error)
            )))
        }
    }

    /// Unequips on `target`. A nil `item` picks the first worn item.
    public func unequipItem(
        _ item: FormID?, on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome> {
        guard let equipment else { return InventoryResult(.noEquipment) }
        guard let holder = holder(for: target) else {
            return InventoryResult(note(.noEquipTarget(target)))
        }
        guard let chosen = item ?? equipment.equipped(on: holder).first else {
            return InventoryResult(note(.wearingNothing(target: label(target))))
        }
        let changed = equipment.unequip(chosen, on: holder)
        let outcome = note(.unequipped(
            item: name(of: chosen),
            target: label(target),
            changed: changed
        ))
        return InventoryResult(outcome, commands: [.equipmentChanged(holder)])
    }

    /// What `target` wears. Empty without equipment or without a target.
    public func equippedReadout(on target: EquipmentTargetSelector) -> [EquippedItemReadout] {
        guard let equipment, let holder = holder(for: target) else { return [] }
        return equipment.equipped(on: holder).map { item in
            EquippedItemReadout(
                name: name(of: item),
                occupancy: InventoryCore.describe(equipment.occupancy(of: item)),
                enchantment: world.enchantmentLine(of: item, on: holder.key)
            )
        }
    }

    /// The nearest resident ACHR as a holder. The readout and the actions
    /// share it, so they agree on which actor "nearest" means.
    public func nearestActorHolder() -> InventoryHolder? {
        guard
            let runtime,
            let entry = world.nearestActorEntry(),
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
