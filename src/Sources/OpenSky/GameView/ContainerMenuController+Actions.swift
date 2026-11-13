// Transactions, merchant nomination, barter and the readout snapshot for the
// container and barter menus. Every refusal lands in `lastActionText` and
// leaves the world untouched.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyQuestsInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension ContainerMenuController {
    // MARK: - Merchant nomination

    /// Binds one container interaction as the menu's target. The holder
    /// matches the one a crosshair search opens.
    @discardableResult
    func nominate(_ interaction: PlacedInteraction) -> Bool {
        guard let holder = game.inventory.containerTrade.containerHolder(for: interaction)
        else { return false }
        target(holder, name: interaction.name)
        return true
    }

    // MARK: - Barter

    /// Opens the barter menu on `actor`'s vendor stock, as
    /// `Actor.ShowBarterMenu` does. `override` is the dev readout's vendor faction.
    ///
    /// - Returns: a readout line, which also lands in the menu's action text.
    @discardableResult
    func openBarter(
        with actor: ReferenceKey,
        vendorFaction override: ReferenceKey? = nil
    ) -> String {
        let found = deals.barterPartner(with: actor, vendorFaction: override)
        guard let partner = found.partner else { return note(found.line) }
        game.dialogueMenu.close()
        close()
        target(partner.holder, name: partner.name, vendor: partner.vendor, merchant: actor)
        setMode(.barter)
        open()
        return note(found.line)
    }

    /// Opens the container menu on a living actor's own items, as a follower's
    /// trade does. The holder is the one a corpse search uses.
    func openInventory(of actor: ReferenceKey) {
        guard let partner = deals.actorPartner(of: actor) else { return }
        game.dialogueMenu.close()
        close()
        target(partner.holder, name: partner.name)
        teammateTarget = actor
        setMode(.container)
        open()
    }

    /// Opens `actor`'s pockets, as activating a living actor while sneaking does
    /// (UESP "Skyrim:Pickpocket"). False when the actor has no inventory to show. A target
    /// that caught the player lately refuses with a notice, which also counts as handled.
    @discardableResult
    func openPickpocket(of actor: ReferenceKey) -> Bool {
        if deals.showsPocketRefusal(by: actor) {
            return true
        }
        openInventory(of: actor)
        guard isOpen, container?.key == actor else { return false }
        teammateTarget = nil
        pickpocketTarget = actor
        note("Pickpocketing \(containerName ?? actor.description).")
        return true
    }

    // MARK: - Transactions

    /// Take, store, buy or sell, according to the mode and the side. A stack of
    /// more than five asks how many first, as the vanilla movies do.
    func activateSelection() {
        guard let entry = model.selectedEntry else {
            note("No row selected.")
            return
        }
        if
            let prompt = InventoryQuantityPrompt.asking(
                item: entry.item, name: entry.name, count: entry.count,
                verb: pickpocketTarget != nil && model.side == .player ? "Place"
                    : model.transferLabel
            )
        {
            quantity = prompt
            note(prompt.text)
            return
        }
        move(entry, count: 1)
    }

    /// Moves `count` of `entry`. A sale the merchant cannot pay waits for a confirm.
    func move(_ entry: InventoryMenuEntry, count: Int32, acceptingLess: Bool = false) {
        guard game.inventory.runtime != nil, let container else {
            note(InventoryCore.noRuntimeText)
            return
        }
        if pickpocketTarget != nil, mode == .container {
            let outcome = deals.pickpocket(entry, count: count, side: model.side, target: container)
            note(outcome.text)
            if outcome.took, !pickedOpenPockets {
                pickedOpenPockets = true
                deals.notePocketsPicked()
            }
            if outcome.caught {
                close()
            }
            refreshModel()
            return
        }
        let transfer: ContainerTransfer = switch (mode, model.side) {
        case (.container, .container): .take
        case (.container, .player): .store
        case (.barter, .container): .buy
        case (.barter, .player): .sell
        }
        let isTeammateTrade = teammateTarget != nil
        if
            isTeammateTrade,
            let notice = deals.teammateRefusal(
                transfer, (entry, count), of: container, name: containerName
            )
        {
            note(notice)
            return
        }
        do {
            var request = ContainerTransferRequest(
                transfer, item: entry.item, name: entry.name, container: container,
                vendor: vendor
            )
            request.count = count
            request.merchant = merchant
            request.acceptingLess = acceptingLess
            let outcome = try game.inventory.containerTrade.transfer(request)
            if case .merchantShort = outcome {
                pendingSale = (entry, count)
                note(outcome.text(texts: game.inventory.containerTrade.tradeTexts)
                    + " Accept sells for the merchant's gold; cancel keeps the item.")
            } else {
                note(outcome.text(texts: game.inventory.containerTrade.tradeTexts))
            }
        } catch {
            note("\(model.transferLabel) refused: \(String(describing: error))")
        }
        refreshModel()
    }

    func takeAll() {
        guard game.inventory.runtime != nil, let container else {
            note(InventoryCore.noRuntimeText)
            return
        }
        guard mode == .container, pickpocketTarget == nil else {
            note("Take all is a container action, not a barter or pickpocket one.")
            return
        }
        note(deals.takeAll(from: container, teammate: teammateTarget != nil))
        refreshModel()
    }

    @discardableResult
    private func note(_ text: String) -> String {
        noteAction(text)
        return text
    }

    // MARK: - Readout

    var snapshot: ContainerMenuControlSnapshot {
        ContainerMenuControlSnapshot(
            entryLines: model.active.entries.map(\.readoutLine),
            selectedIndex: model.active.selectedIndex
        )
    }
}

/// The world reads and rules behind the container menu's deals: who trades, what a
/// pocket take does, and what a follower refuses. It holds the host, not the menu.
struct ContainerMenuDeals {
    let game: any ContainerMenuHost

    /// The merchant's chest and vendor, with the readout line. No partner when the
    /// actor does not trade now; the line then says why.
    func barterPartner(
        with actor: ReferenceKey, vendorFaction override: ReferenceKey?
    ) -> (partner: ContainerDealPartner?, line: String) {
        let result = game.inventory.vendors?.counterparty(for: actor, vendorFaction: override)
            ?? .failure(.notAMerchant)
        let counterparty: BarterCounterparty
        switch result {
        case let .success(found):
            counterparty = found
        case .failure(.notAMerchant):
            return (nil, "\(game.dialogueWorld.speakerLabel(for: actor)) is not a merchant.")
        case let .failure(.chestNotResident(factionName)):
            return (nil, "\(factionName)'s merchant chest is not streamed in.")
        case let .failure(.notTrading(factionName, reason)):
            return (nil, "\(factionName) is not trading: \(reason.text).")
        }
        let partner = ContainerDealPartner(
            holder: counterparty.holder,
            name: game.dialogueWorld.speakerLabel(for: actor),
            vendor: counterparty.vendor
        )
        return (partner, "Bartering with \(counterparty.vendor.factionName).")
    }

    /// A living actor's own items, under the holder a corpse search uses.
    func actorPartner(of actor: ReferenceKey) -> ContainerDealPartner? {
        guard
            game.inventory.runtime != nil,
            let entry = game.streamer.referenceEntry(key: actor),
            let placed = entry.placedActor
        else { return nil }
        return ContainerDealPartner(
            holder: InventoryHolder(
                key: actor, owner: .actor(base: placed.base),
                cell: game.streamer.cellLocation(of: actor)
            ),
            name: game.dialogueWorld.speakerLabel(for: actor)
        )
    }

    /// Shows the notice of a target that caught the player lately. True when it refuses.
    func showsPocketRefusal(by actor: ReferenceKey) -> Bool {
        guard game.inventory.pickpocketing.pickpocketRefused(by: actor) else { return false }
        let text = game.mapWorld.settingTexts(PickpocketText.self)[.caughtBefore]
        game.hud.showNotification(game.dialogueWorld.speakerLabel(for: actor) + text)
        return true
    }

    /// A take from the pocket side, a place from the player side. A caught try
    /// shows the notice; the menu then closes, because the target noticed.
    func pickpocket(
        _ entry: InventoryMenuEntry, count: Int32, side: ContainerMenuModel.Side,
        target: InventoryHolder
    ) -> PickpocketReply {
        let roll = Float.random(in: 0 ..< 100)
        let outcome = side == .container
            ? game.inventory.pickpocketing.pickpocket(
                entry.item, count: count, named: entry.name, from: target, roll: roll
            )
            : game.inventory.pickpocketing.plant(
                entry.item, count: count, named: entry.name, into: target, roll: roll
            )
        var took = false
        if case .took = outcome {
            took = true
            game.worldState.incrementMiscStat("Items Pickpocketed")
        }
        if outcome.wasCaught {
            game.hud.showNotification(game.mapWorld.settingTexts(PickpocketText.self)[.caught])
        }
        return PickpocketReply(text: outcome.text, took: took, caught: outcome.wasCaught)
    }

    /// Counts the first successful take from one open set of pockets.
    func notePocketsPicked() {
        game.worldState.incrementMiscStat("Pockets Picked")
    }

    /// Shows the follower's refusal on the HUD, and returns it. Nil when the move is allowed.
    func teammateRefusal(
        _ transfer: ContainerTransfer, _ move: (entry: InventoryMenuEntry, count: Int32),
        of teammate: InventoryHolder, name: String?
    ) -> String? {
        guard
            let refusal = game.inventory.teammateTrades.teammateRefusal(
                transfer, item: move.entry.item, count: move.count, teammate: teammate
            )
        else { return nil }
        let text = game.mapWorld.settingTexts(TeammateTradeText.self)[refusal]
        let notice = refusal == .overencumbered ? "\(name ?? "") \(text)" : text
        game.hud.showNotification(notice)
        return notice
    }

    /// Equips or unequips the row's item on the player, and returns the outcome line.
    func toggleEquip(_ entry: InventoryMenuEntry) -> String {
        entry.isEquipped
            ? game.inventoryWorld.run(game.inventory.equipmentChanges.unequipItem(
                entry.item,
                on: .player
            )).text
            : game.inventoryWorld.run(game.inventory.equipmentChanges.equipItem(
                entry.item,
                on: .player
            )).text
    }

    func takeAll(from container: InventoryHolder, teammate: Bool) -> String {
        let outcome = teammate
            ? game.inventory.teammateTrades.takeAllFromTeammate(container) : game.inventory
            .containerTrade.takeAll(from: container)
        return outcome.text
    }
}

/// Whom the container menu deals with: the holder, its shown name, and, for barter,
/// the vendor.
struct ContainerDealPartner {
    let holder: InventoryHolder
    let name: String
    var vendor: Vendor?
}

/// What one pickpocket try showed, and whether it took the item or was caught.
struct PickpocketReply {
    let text: String
    let took: Bool
    let caught: Bool
}
