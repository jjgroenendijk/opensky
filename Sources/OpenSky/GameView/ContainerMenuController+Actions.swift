// Transactions, merchant nomination, barter and the readout snapshot for the
// container and barter menus. Every refusal lands in `lastActionText` and
// leaves the world untouched.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyQuestsInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension ContainerMenuController {
    // MARK: - Merchant nomination

    /// Binds one container interaction as the menu's target. The holder
    /// matches the one a crosshair search opens.
    @discardableResult
    func nominate(_ interaction: PlacedInteraction) -> Bool {
        guard let holder = game.inventory.containerHolder(for: interaction) else { return false }
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
        let result = game.inventory.vendors?.counterparty(for: actor, vendorFaction: override)
            ?? .failure(.notAMerchant)
        let counterparty: BarterCounterparty
        switch result {
        case let .success(found):
            counterparty = found
        case .failure(.notAMerchant):
            return note("\(game.dialogueWorld.speakerLabel(for: actor)) is not a merchant.")
        case let .failure(.chestNotResident(factionName)):
            return note("\(factionName)'s merchant chest is not streamed in.")
        case let .failure(.notTrading(factionName, reason)):
            return note("\(factionName) is not trading: \(reason.text).")
        }
        game.dialogueMenu.close()
        close()
        target(
            counterparty.holder,
            name: game.dialogueWorld.speakerLabel(for: actor),
            vendor: counterparty.vendor,
            merchant: actor
        )
        setMode(.barter)
        open()
        return note("Bartering with \(counterparty.vendor.factionName).")
    }

    /// Opens the container menu on a living actor's own items, as a follower's
    /// trade does. The holder is the one a corpse search uses.
    func openInventory(of actor: ReferenceKey) {
        guard
            game.inventory.runtime != nil,
            let entry = game.streamer?.referenceEntry(key: actor),
            let placed = entry.placedActor
        else { return }
        game.dialogueMenu.close()
        close()
        target(
            InventoryHolder(
                key: actor, owner: .actor(base: placed.base),
                cell: game.streamer?.cellLocation(of: actor)
            ),
            name: game.dialogueWorld.speakerLabel(for: actor)
        )
        setMode(.container)
        open()
    }

    /// Opens `actor`'s pockets, as activating a living actor while sneaking does
    /// (UESP "Skyrim:Pickpocket"). False when the actor has no inventory to show.
    @discardableResult
    func openPickpocket(of actor: ReferenceKey) -> Bool {
        openInventory(of: actor)
        guard isOpen, container?.key == actor else { return false }
        pickpocketTarget = actor
        note("Pickpocketing \(containerName ?? actor.description).")
        return true
    }

    /// A take from the pocket side, a place from the player side. A failure closes
    /// the pockets, because the target noticed.
    private func pickpocket(
        _ entry: InventoryMenuEntry, count: Int32, side: ContainerMenuModel.Side,
        target: InventoryHolder
    ) {
        let roll = Float.random(in: 0 ..< 100)
        let outcome = side == .container
            ? game.inventory.pickpocket(
                entry.item, count: count, named: entry.name, from: target, roll: roll
            )
            : game.inventory.plant(
                entry.item, count: count, named: entry.name, into: target, roll: roll
            )
        note(outcome.text)
        let worldState = game.inventoryWorld.game.worldState
        if case .took = outcome {
            worldState.incrementMiscStat("Items Pickpocketed")
            if !pickedOpenPockets {
                pickedOpenPockets = true
                worldState.incrementMiscStat("Pockets Picked")
            }
        }
        if outcome.wasCaught {
            close()
            game.hud.showNotification(game.mapWorld.settingTexts(PickpocketText.self)[.caught])
        }
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
            pickpocket(entry, count: count, side: model.side, target: container)
            refreshModel()
            return
        }
        let transfer: ContainerTransfer = switch (mode, model.side) {
        case (.container, .container): .take
        case (.container, .player): .store
        case (.barter, .container): .buy
        case (.barter, .player): .sell
        }
        do {
            let outcome = try game.inventory.transfer(
                transfer, item: entry.item, count: count, named: entry.name,
                container: container, vendor: vendor, merchant: merchant,
                acceptingLess: acceptingLess
            )
            if case .merchantShort = outcome {
                pendingSale = (entry, count)
                note(outcome.text(texts: game.inventory.tradeTexts)
                    + " Accept sells for the merchant's gold; cancel keeps the item.")
            } else {
                note(outcome.text(texts: game.inventory.tradeTexts))
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
        note(game.inventory.takeAll(from: container).text)
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
