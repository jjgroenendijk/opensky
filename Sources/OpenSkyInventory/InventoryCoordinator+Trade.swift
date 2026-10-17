// The container and barter menu transactions. The menu owns the selection;
// these move the items and the gold. See docs/engine/barter.md.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
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
    public func transfer(
        _ transfer: ContainerTransfer,
        item: FormID,
        named name: String,
        container: InventoryHolder,
        vendor: Vendor?,
        merchant: ReferenceKey? = nil
    ) throws -> TradeOutcome {
        guard let runtime else { return .unavailable }
        switch transfer {
        case .take:
            // Through the session, so a single take marks theft the same way
            // "take all" does.
            let session = ContainerSession(runtime: runtime, container: container)
            let bounty = try session.take(item)
            reportTaken([InventoryStack(item: item, count: 1)], from: session)
            return .took(item: name, bounty: bounty)
        case .store:
            try runtime.inventory.transfer(item, count: 1, from: .player, to: container)
            storyEvents?.reportStoryEvent(.removeItem(
                item, reference: container.key, owner: nil, how: .putInContainer
            ))
            return .stored(name)
        case .buy:
            let bought: BarterTransaction
            do {
                bought = try barterSession(runtime, container, vendor, merchant).buy(item)
            } catch BarterError.playerCannotAfford {
                return .tooExpensive
            }
            storyEvents?.reportStoryEvent(.addItem(
                item, from: container.key, owner: nil, how: .buy
            ))
            return .bought(item: name, gold: bought.gold)
        case .sell:
            let sold: BarterTransaction
            do {
                sold = try barterSession(runtime, container, vendor, merchant).sell(item)
            } catch let BarterError.merchantCannotAfford(price, gold) {
                return .merchantShort(price: price, gold: gold)
            }
            storyEvents?.reportStoryEvent(.removeItem(
                item, reference: container.key, owner: nil, how: .given
            ))
            return .sold(item: name, gold: sold.gold)
        }
    }

    public func takeAll(from container: InventoryHolder) -> ItemActionOutcome {
        guard let runtime else { return .unavailable }
        do {
            let session = ContainerSession(runtime: runtime, container: container)
            let moved = try session.takeAll()
            reportTaken(moved, from: session)
            return .tookAll(moved)
        } catch {
            return .failed(action: "Take all", reason: String(describing: error))
        }
    }

    private func barterSession(
        _ runtime: WorldItemRuntime,
        _ container: InventoryHolder,
        _ vendor: Vendor?,
        _ merchant: ReferenceKey?
    ) -> BarterSession {
        BarterSession(
            runtime: runtime,
            merchant: container,
            pricing: barterPricing(with: merchant),
            rules: vendors?.rules(for: vendor) ?? .unrestricted
        )
    }

    /// The prices the player trades at with `merchant`: the player's live Speech skill,
    /// then the player's `Mod Buy Prices` and `Mod Sell Prices` with the merchant bound.
    public func barterPricing(with merchant: ReferenceKey?) -> BarterPricing {
        guard let world else { return barterPricing }
        let subjects = PerkEvaluationSubjects(owner: .player, target: merchant)
        let modifier = { (entryPoint: PerkEntryPoint) in
            Double(world.perkModified(
                1, at: entryPoint, on: .player, subjects: subjects, seams: ConditionContext()
            ))
        }
        return barterPricing.trading(
            speechSkill: world.playerSpeechSkill().map(Double.init)
                ?? barterPricing.speechSkill,
            buyModifier: modifier(.modBuyPrices),
            sellModifier: modifier(.modSellPrices)
        )
    }
}

extension InventoryCoordinator {
    /// `AIPL` per stack taken. A container that is an actor is a dead body here,
    /// because pickpocketing does not use this path.
    func reportTaken(_ stacks: [InventoryStack], from session: ContainerSession) {
        let how: StoryAcquireType = switch (session.ownership.isTheft, session.container.owner) {
        case (true, _): .steal
        case (false, .actor): .deadBody
        default: .container
        }
        for stack in stacks {
            storyEvents?.reportStoryEvent(.addItem(
                stack.item, from: session.container.key, owner: nil, how: how
            ))
        }
    }
}
