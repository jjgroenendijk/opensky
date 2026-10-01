// The container and barter menu transactions. The menu owns the selection;
// these move the items and the gold. See docs/engine/barter.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    /// The holder a container interaction stands for, resolved the way
    /// `WorldItemRuntime.openContainer` resolves it. Nil when nothing resident
    /// holds the reference, because a made-up key would match nothing else.
    public func containerHolder(for interaction: PlacedInteraction) -> InventoryHolder? {
        guard
            runtime != nil,
            let references = runtime?.references,
            let entry = references.referenceEntry(formID: interaction.reference)
        else { return nil }
        return InventoryHolder(
            key: entry.key,
            owner: .container(base: interaction.base),
            cell: references.cellLocation(of: entry.key)
        )
    }

    /// Every resident container that could be nominated as a merchant, with
    /// its holder.
    public func merchantCandidates() -> [(
        interaction: PlacedInteraction,
        holder: InventoryHolder
    )] {
        (world?.containerInteractions() ?? []).compactMap { interaction in
            containerHolder(for: interaction).map { (interaction, $0) }
        }
    }

    /// Moves one `item` in the direction `transfer` names. A new session per
    /// call, so a merchant nominated again mid-menu leaves nothing stale.
    ///
    /// - Returns: the outcome sentence.
    public func transfer(
        _ transfer: ContainerTransfer,
        item: FormID,
        named name: String,
        container: InventoryHolder,
        vendor: Vendor?
    ) throws -> String {
        guard let runtime else { return InventoryCore.noRuntimeText }
        switch transfer {
        case .take:
            // Through the session, so a single take marks theft the same way
            // "take all" does.
            let bounty = try ContainerSession(runtime: runtime, container: container).take(item)
            return InventoryCore.takeSentence(item: name, bounty: bounty)
        case .store:
            try runtime.inventory.transfer(item, count: 1, from: .player, to: container)
            return "Stored \(name)."
        case .buy:
            let bought = try barterSession(runtime, container, vendor).buy(item)
            return "Bought \(name) for \(bought.gold) gold."
        case .sell:
            let sold = try barterSession(runtime, container, vendor).sell(item)
            return "Sold \(name) for \(sold.gold) gold."
        }
    }

    public func takeAll(from container: InventoryHolder) -> String {
        guard let runtime else { return InventoryCore.noRuntimeText }
        do {
            let moved = try ContainerSession(runtime: runtime, container: container).takeAll()
            return InventoryCore.takeAllSentence(moved)
        } catch {
            return "Take all failed: \(String(describing: error))"
        }
    }

    private func barterSession(
        _ runtime: WorldItemRuntime,
        _ container: InventoryHolder,
        _ vendor: Vendor?
    ) -> BarterSession {
        BarterSession(
            runtime: runtime,
            merchant: container,
            pricing: barterPricing,
            rules: vendors?.rules(for: vendor) ?? .unrestricted
        )
    }
}
