// The Items readout and the Inventory & Equipment readout read and write the
// coordinator through these two providers. Ownership is reported, never
// enforced.

public import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryCoordinator.ItemPanels {
    var itemControlSnapshot: ItemControlSnapshot {
        guard let runtime = coordinator.runtime else { return .unavailable }
        return ItemControlSnapshot(
            playerStacks: coordinator
                .readout(runtime.inventory.inventory(of: runtime.player).stacks),
            containerName: coordinator.session == nil ? nil : coordinator.sessionName,
            lastActionText: coordinator.lastAction.text
        )
    }
}

extension InventoryCoordinator.ItemPanels {
    var inventoryEquipmentSnapshot: InventoryEquipmentSnapshot {
        guard let runtime = coordinator.runtime else { return .unavailable }
        let container = coordinator.session?.container
        return InventoryEquipmentSnapshot(
            isAvailable: true,
            hasOpenContainer: coordinator.session != nil,
            openContainerName: coordinator.session == nil ? nil : coordinator.sessionName,
            playerStacks: coordinator
                .readout(runtime.inventory.inventory(of: runtime.player).stacks),
            playerGold: runtime.inventory.goldCount(of: runtime.player),
            playerWeight: coordinator.armourWeights.playerCarriedWeight,
            containerStacks: coordinator.readout(coordinator.session?.contents ?? []),
            containerGold: container.map { runtime.inventory.goldCount(of: $0) } ?? 0,
            targetOwnership: targetOwnership(),
            equipTarget: coordinator.inspectionTarget,
            equipInspection: equipInspection(),
            enchantmentCache: coordinator.world.enchantmentCacheReadout,
            lastActionText: coordinator.lastGrant.text
        )
    }

    /// Adds the stack on purpose. It lands in the journal and the save exactly
    /// like a take does.
    @discardableResult
    func grantItem(
        _ item: FormID, count: Int32, to target: InventoryGrantTarget
    ) -> GrantActionOutcome {
        guard let runtime = coordinator.runtime else { return .unavailable }
        let isKnown = runtime.inventory.baselines.items.definition(item) != nil
        if let refusal = InventoryCore.grantRefusal(item: item, count: count, isKnown: isKnown) {
            return coordinator.noteGrant(refusal)
        }
        let holder = switch target {
        case .player: runtime.player
        case .openContainer: coordinator.session?.container
        }
        guard let holder else { return coordinator.noteGrant(.noOpenContainer) }
        do {
            try runtime.inventory.add(item, count: count, to: holder)
            return coordinator.noteGrant(.granted(
                count: count,
                item: coordinator.name(of: item),
                to: target
            ))
        } catch {
            return coordinator.noteGrant(.failed(reason: String(describing: error)))
        }
    }

    /// `XOWN` and `XRNK` of the crosshair target. A target the resident index
    /// cannot resolve still reports, with unknown ownership.
    public func targetOwnership() -> ReferenceOwnershipReadout? {
        guard let interaction = coordinator.world.crosshairInteraction else { return nil }
        let entry = coordinator.runtime?.references?.referenceEntry(formID: interaction.reference)
        let placed = entry?.placedReference
        // A loose item asks with its value, which a friend's allowance may cover.
        let item = interaction.action == .take ? interaction.base : nil
        let verdict = entry.flatMap {
            coordinator.runtime?.crime?.verdict(on: $0.key, item: item, by: .player)
        } ?? .unowned
        return ReferenceOwnershipReadout(
            name: interaction.name,
            reference: interaction.reference,
            owner: placed?.owner,
            factionRank: placed?.ownerFactionRank,
            isTheft: verdict.isTheft,
            bounty: entry.map {
                coordinator.world.theftBounty(of: interaction.base, from: $0.key)
            } ?? 0
        )
    }

    private func equipInspection() -> EquipInspectReadout {
        switch coordinator.inspectionTarget {
        case .player:
            guard let runtime = coordinator.runtime else { return .unresolved }
            return EquipInspectReadout(
                name: "the player",
                equipped: coordinator.equipmentChanges.equippedReadout(on: .player),
                // The player has no rendered body, so no cell build reports
                // skips for them. Empty is the true answer.
                appearanceSkips: [],
                usesRuntimeEquipment: runtime.inventory.hasRuntimeInventory(runtime.player)
            )
        case .nearestActor:
            guard let holder = coordinator.equipmentChanges.nearestActorHolder()
            else { return .unresolved }
            let entry = coordinator.runtime?.references?.referenceEntry(key: holder.key)
            return EquipInspectReadout(
                name: InventoryCore.actorName(holder),
                equipped: coordinator.equipmentChanges.equippedReadout(on: .nearestActor),
                appearanceSkips: entry.map {
                    coordinator.world.appearanceSkipReasons(forActor: $0.formID)
                } ?? [],
                usesRuntimeEquipment: coordinator.runtime?.inventory
                    .hasRuntimeInventory(holder) ?? false
            )
        }
    }
}
