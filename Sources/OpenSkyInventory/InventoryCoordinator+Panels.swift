// The Items panel and the Inventory & Equipment panel read and write the
// coordinator through these two providers. Ownership is reported, never
// enforced.

import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryCoordinator: ItemControlProviding {
    public var itemControlSnapshot: ItemControlSnapshot {
        guard let runtime else { return .unavailable }
        let interaction = world?.crosshairInteraction
        return ItemControlSnapshot(
            isAvailable: true,
            targetName: interaction?.name,
            targetIsTakeable: interaction?.action == .take,
            targetIsContainer: interaction?.action == .search,
            playerStacks: readout(runtime.inventory.inventory(of: runtime.player).stacks),
            playerWeight: runtime.inventory.carriedWeight(of: runtime.player),
            playerGold: runtime.inventory.goldCount(of: runtime.player),
            containerName: session == nil ? nil : sessionName,
            containerStacks: readout(session?.contents ?? []),
            spawnedObjectCount: runtime.store.snapshot().entries.count {
                $0.delta.component(ReferenceSpawnState.self) != nil
            },
            lastActionText: lastActionText,
            playerEquipped: equippedReadout(on: .player),
            nearestActorName: nearestActorHolder().map(InventoryCore.actorName),
            nearestActorEquipped: equippedReadout(on: .nearestActor)
        )
    }
}

extension InventoryCoordinator: InventoryEquipmentControlProviding {
    public var inventoryEquipmentInspectionTarget: EquipmentTargetSelector {
        get { inspectionTarget }
        set { inspectionTarget = newValue }
    }

    public var inventoryEquipmentSnapshot: InventoryEquipmentSnapshot {
        guard let runtime else { return .unavailable }
        let container = session?.container
        return InventoryEquipmentSnapshot(
            isAvailable: true,
            hasOpenContainer: session != nil,
            openContainerName: session == nil ? nil : sessionName,
            playerStacks: readout(runtime.inventory.inventory(of: runtime.player).stacks),
            playerGold: runtime.inventory.goldCount(of: runtime.player),
            playerWeight: runtime.inventory.carriedWeight(of: runtime.player),
            containerStacks: readout(session?.contents ?? []),
            containerGold: container.map { runtime.inventory.goldCount(of: $0) } ?? 0,
            targetOwnership: targetOwnership(),
            equipTarget: inspectionTarget,
            equipInspection: equipInspection(),
            enchantmentCache: world?.enchantmentCacheReadout ?? .empty,
            lastActionText: lastGrantText
        )
    }

    /// Adds the stack on purpose. It lands in the journal and the save exactly
    /// like a take does.
    @discardableResult
    public func grantItem(_ item: FormID, count: Int32, to target: InventoryGrantTarget) -> String {
        guard let runtime else {
            return InventoryEquipmentSnapshot.unavailable.lastActionText
        }
        let isKnown = runtime.inventory.baselines.items.definition(item) != nil
        if let refusal = InventoryCore.grantRefusal(item: item, count: count, isKnown: isKnown) {
            return noteGrant(refusal)
        }
        let holder = switch target {
        case .player: runtime.player
        case .openContainer: session?.container
        }
        guard let holder else {
            return noteGrant("Grant refused: no container is open.")
        }
        do {
            try runtime.inventory.add(item, count: count, to: holder)
            return noteGrant("Granted \(count) × \(name(of: item)) to \(target.label).")
        } catch {
            return noteGrant("Grant failed: \(String(describing: error))")
        }
    }

    /// `XOWN` and `XRNK` of the crosshair target. A target the resident index
    /// cannot resolve still reports, with unknown ownership.
    public func targetOwnership() -> ReferenceOwnershipReadout? {
        guard let interaction = world?.crosshairInteraction else { return nil }
        let entry = runtime?.references?.referenceEntry(formID: interaction.reference)
        let placed = entry?.placedReference
        let verdict = entry.flatMap { runtime?.crime?.verdict(on: $0.key) } ?? .unowned
        return ReferenceOwnershipReadout(
            name: interaction.name,
            reference: interaction.reference,
            owner: placed?.owner,
            factionRank: placed?.ownerFactionRank,
            isTheft: verdict.isTheft,
            bounty: entry.map {
                world?.theftBounty(of: interaction.base, from: $0.key) ?? 0
            } ?? 0
        )
    }

    private func equipInspection() -> EquipInspectReadout {
        switch inspectionTarget {
        case .player:
            guard let runtime else { return .unresolved }
            return EquipInspectReadout(
                name: "the player",
                equipped: equippedReadout(on: .player),
                // The player has no rendered body, so no cell build reports
                // skips for them. Empty is the true answer.
                appearanceSkips: [],
                usesRuntimeEquipment: runtime.inventory.hasRuntimeInventory(runtime.player)
            )
        case .nearestActor:
            guard let holder = nearestActorHolder() else { return .unresolved }
            let entry = runtime?.references?.referenceEntry(key: holder.key)
            return EquipInspectReadout(
                name: InventoryCore.actorName(holder),
                equipped: equippedReadout(on: .nearestActor),
                appearanceSkips: entry.map {
                    world?.appearanceSkipReasons(forActor: $0.formID) ?? []
                } ?? [],
                usesRuntimeEquipment: runtime?.inventory.hasRuntimeInventory(holder) ?? false
            )
        }
    }
}
