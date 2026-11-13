// Equip and unequip on the player or the nearest NPC. An equip on the NPC
// queues a cell rebuild, so the actor redraws from its new equipped set.

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryCoordinator.EquipmentChanges {
    /// Equips on `target`, unequipping whatever conflicts. A nil `item` picks
    /// the first equippable stack.
    public func equipItem(
        _ item: FormID?, on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome> {
        guard let equipment = coordinator.equipment else { return InventoryResult(.noEquipment) }
        guard let holder = holder(for: target) else {
            return InventoryResult(coordinator.note(.noEquipTarget(target)))
        }
        let state = equipment.inventory.inventory(of: holder)
        guard
            let chosen = item ?? InventoryCore.firstEquippable(
                in: state, occupancy: equipment.occupancy(of:)
            )
        else { return InventoryResult(coordinator.note(.nothingEquippable)) }
        do {
            let change = try equipment.equip(chosen, on: holder)
            let outcome = coordinator.note(.equipped(
                item: coordinator.name(of: chosen),
                target: label(target),
                changed: change.changed,
                unequipped: change.unequipped.map { coordinator.name(of: $0) }
            ))
            return InventoryResult(outcome, commands: [.equipmentChanged(holder)])
        } catch {
            return InventoryResult(coordinator.note(.failed(
                action: "Equip",
                reason: String(describing: error)
            )))
        }
    }

    /// Unequips on `target`. A nil `item` picks the first worn item.
    public func unequipItem(
        _ item: FormID?, on target: EquipmentTargetSelector
    ) -> InventoryResult<ItemActionOutcome> {
        guard let equipment = coordinator.equipment else { return InventoryResult(.noEquipment) }
        guard let holder = holder(for: target) else {
            return InventoryResult(coordinator.note(.noEquipTarget(target)))
        }
        guard let chosen = item ?? equipment.equipped(on: holder).first else {
            return InventoryResult(coordinator.note(.wearingNothing(target: label(target))))
        }
        let changed = equipment.unequip(chosen, on: holder)
        let outcome = coordinator.note(.unequipped(
            item: coordinator.name(of: chosen),
            target: label(target),
            changed: changed
        ))
        return InventoryResult(outcome, commands: [.equipmentChanged(holder)])
    }

    /// What `target` wears. Empty without equipment or without a target.
    func equippedReadout(on target: EquipmentTargetSelector) -> [EquippedItemReadout] {
        guard
            let equipment = coordinator.equipment,
            let holder = holder(for: target) else { return [] }
        return equipment.equipped(on: holder).map { item in
            EquippedItemReadout(
                name: coordinator.name(of: item),
                occupancy: InventoryCore.describe(equipment.occupancy(of: item)),
                enchantment: coordinator.world.enchantmentLine(of: item, on: holder.key)
            )
        }
    }

    /// The nearest resident ACHR as a holder. The readout and the actions
    /// share it, so they agree on which actor "nearest" means.
    func nearestActorHolder() -> InventoryHolder? {
        guard
            let runtime = coordinator.runtime,
            let entry = coordinator.world.nearestActorEntry(),
            let actor = entry.placedActor
        else { return nil }
        return runtime.actorHolder(entry: entry, base: actor.base)
    }

    func holder(for target: EquipmentTargetSelector) -> InventoryHolder? {
        switch target {
        case .player: coordinator.runtime?.player
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
