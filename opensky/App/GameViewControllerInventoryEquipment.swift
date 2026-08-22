// Live bridge for the World > Inventory & Equipment sidebar panel (issue #180,
// roadmap item 12.2.4). Satellite of GameViewControllerItems.swift, which owns
// the take/drop/container half of the same `WorldItemRuntime`.
//
// The gate destination reads three things nothing else surfaces and writes one:
//
// * The grant, which is the only new mutation in the milestone's last item. It
//   is `InventoryRuntime.add` and nothing more, so a granted stack lands in the
//   journal, the dirty counts and the save exactly like a take does, and the
//   conservation the rest of M12 asserts still holds — a grant creates items on
//   purpose and says so, rather than a transfer quietly failing to conserve.
// * Ownership, read straight off the crosshair target's `PlacedReference`
//   (`XOWN`/`XRNK` from issue #175). Reported, never enforced.
// * The inspected owner's equipped set plus the `AppearanceSkip` lines its
//   cell's last build reported, so a piece that occupies a slot but drew
//   nothing is distinguishable from an equip that silently did nothing.
//
// Everything degrades to a stated non-answer rather than a crash, matching the
// rest of the item bridge: no game data means no item index, which the panel
// reports as unavailable instead of showing a convincing empty inventory.

import AppKit

extension GameViewController: InventoryEquipmentControlProviding {
    var inventoryEquipmentInspectionTarget: EquipmentTargetSelector {
        get { worldItems.inspectionTarget }
        set { worldItems.inspectionTarget = newValue }
    }

    var inventoryEquipmentSnapshot: InventoryEquipmentSnapshot {
        guard let runtime = worldItems.runtime else { return .unavailable }
        let session = worldItems.session
        let container = session?.container
        return InventoryEquipmentSnapshot(
            isAvailable: true,
            hasOpenContainer: session != nil,
            openContainerName: session == nil ? nil : worldItems.sessionName,
            playerStacks: readout(runtime.inventory.inventory(of: runtime.player).stacks),
            playerGold: runtime.inventory.goldCount(of: runtime.player),
            playerWeight: runtime.inventory.carriedWeight(of: runtime.player),
            containerStacks: readout(session?.contents ?? []),
            containerGold: container.map { runtime.inventory.goldCount(of: $0) } ?? 0,
            targetOwnership: targetOwnership(),
            equipTarget: worldItems.inspectionTarget,
            equipInspection: equipInspection(),
            enchantmentCache: enchantments.profiles.readout,
            lastActionText: worldItems.lastGrantText
        )
    }

    @discardableResult
    func grantItem(_ item: FormID, count: Int32, to target: InventoryGrantTarget) -> String {
        guard let runtime = worldItems.runtime else {
            return InventoryEquipmentSnapshot.unavailable.lastActionText
        }
        guard count > 0 else {
            worldItems.lastGrantText = "Grant refused: a count of \(count) is not a stack."
            return worldItems.lastGrantText
        }
        guard runtime.inventory.baselines.items.definition(item) != nil else {
            worldItems.lastGrantText =
                "Grant refused: no loaded plugin describes \(item), so it has no "
                    + "weight, value or name."
            return worldItems.lastGrantText
        }
        guard let holder = grantHolder(for: target, runtime: runtime) else {
            worldItems.lastGrantText = "Grant refused: no container is open."
            return worldItems.lastGrantText
        }
        do {
            try runtime.inventory.add(item, count: count, to: holder)
            worldItems.lastGrantText =
                "Granted \(count) × \(name(of: item)) to \(target.label)."
        } catch {
            worldItems.lastGrantText = "Grant failed: \(String(describing: error))"
        }
        return worldItems.lastGrantText
    }

    // MARK: - Private

    private func grantHolder(
        for target: InventoryGrantTarget,
        runtime: WorldItemRuntime
    ) -> InventoryHolder? {
        switch target {
        case .player: runtime.player
        case .openContainer: worldItems.session?.container
        }
    }

    /// `XOWN`/`XRNK` for whatever the crosshair is on.
    ///
    /// A target the resident index cannot resolve still reports as a target
    /// with unknown ownership rather than as no target, because the crosshair
    /// is plainly on something and a blank readout would say otherwise.
    private func targetOwnership() -> ReferenceOwnershipReadout? {
        guard let interaction = currentInteraction else { return nil }
        let entry = streamer?.referenceEntry(formID: interaction.reference)
        let placed = entry?.placedReference
        let verdict = entry.map { ownershipVerdict(on: $0.key) } ?? .unowned
        return ReferenceOwnershipReadout(
            name: interaction.name,
            reference: interaction.reference,
            owner: placed?.owner,
            factionRank: placed?.ownerFactionRank,
            isTheft: verdict.isTheft,
            bounty: entry.map {
                crime.reporter?.theftBounty(
                    of: interaction.base, count: 1, from: $0.key
                ) ?? 0
            } ?? 0
        )
    }

    /// The equipped set and appearance skips for the selected owner.
    private func equipInspection() -> EquipInspectReadout {
        let target = worldItems.inspectionTarget
        switch target {
        case .player:
            guard let runtime = worldItems.runtime else { return .unresolved }
            return EquipInspectReadout(
                name: "the player",
                equipped: equippedReadout(on: .player),
                // The player has no rendered body until M14, so no cell build
                // ever resolves an appearance for them; an empty list here is
                // the true answer, not a missing one.
                appearanceSkips: [],
                usesRuntimeEquipment: runtime.inventory.hasRuntimeInventory(runtime.player)
            )
        case .nearestActor:
            guard let holder = nearestActorHolder() else { return .unresolved }
            return EquipInspectReadout(
                name: name(ofActor: holder),
                equipped: equippedReadout(on: .nearestActor),
                appearanceSkips: appearanceSkips(for: holder),
                usesRuntimeEquipment: worldItems.runtime?
                    .inventory.hasRuntimeInventory(holder) ?? false
            )
        }
    }

    /// Appearance skips the actor's cell reported at its last build. The
    /// holder's key carries the ACHR's object id, which is what the summary
    /// lines are tagged with.
    private func appearanceSkips(for holder: InventoryHolder) -> [String] {
        guard
            let streamer,
            let entry = streamer.referenceEntry(key: holder.key)
        else { return [] }
        return streamer.appearanceSkipReasons(forActor: entry.formID)
    }
}
