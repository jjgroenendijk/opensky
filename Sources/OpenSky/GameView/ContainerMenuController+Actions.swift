// Transactions, merchant nomination, barter and the panel snapshot for the
// container and barter menus. Every refusal lands in `lastActionText` and
// leaves the world untouched.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension ContainerMenuController {
    // MARK: - Merchant nomination

    var merchantOptions: [ContainerMenuMerchantOption] {
        guard let inventory = game.inventory.runtime?.inventory else { return [] }
        return game.inventory.merchantCandidates().map { interaction, holder in
            ContainerMenuMerchantOption(
                reference: interaction.reference,
                name: interaction.name,
                itemCount: Int(inventory.inventory(of: holder).totalCount),
                gold: inventory.goldCount(of: holder)
            )
        }
    }

    @discardableResult
    func selectMerchant(_ reference: FormID) -> String {
        guard let streamer = game.streamer else {
            return refuseNomination("no cell is loaded")
        }
        guard
            let interaction = streamer.containerInteractions()
                .first(where: { $0.reference == reference })
        else {
            return refuseNomination("\(reference) is not a resident container")
        }
        return nominateAndNote(interaction)
    }

    @discardableResult
    func selectMerchantFromInteraction() -> String {
        guard
            let interaction = game.hud.interactionTarget?.interaction,
            interaction.action == .search
        else {
            return refuseNomination("the crosshair is not on a container")
        }
        return nominateAndNote(interaction)
    }

    /// Binds one container interaction as the menu's target. The holder
    /// matches the one a crosshair search opens.
    @discardableResult
    func nominate(_ interaction: PlacedInteraction) -> Bool {
        guard let holder = game.inventory.containerHolder(for: interaction) else { return false }
        target(holder, name: interaction.name, reference: interaction.reference)
        return true
    }

    private func nominateAndNote(_ interaction: PlacedInteraction) -> String {
        guard nominate(interaction) else {
            return refuseNomination("world items are unavailable, or nothing resident holds it")
        }
        refreshModel()
        return note("Merchant: \(interaction.name).")
    }

    private func refuseNomination(_ reason: String) -> String {
        note("Cannot nominate a merchant: \(reason).")
    }

    // MARK: - Barter

    /// Opens the barter menu on `actor`'s vendor stock, as
    /// `Actor.ShowBarterMenu` does. `override` is the dev panel's vendor faction.
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
        }
        game.dialogueMenu.close()
        close()
        target(
            counterparty.holder,
            name: game.dialogueWorld.speakerLabel(for: actor),
            reference: game.streamer?.referenceEntry(key: counterparty.holder.key)?.formID,
            vendor: counterparty.vendor
        )
        setMode(.barter)
        open()
        return note("Bartering with \(counterparty.vendor.factionName).")
    }

    // MARK: - Transactions

    /// Take, store, buy or sell, according to the mode and the side.
    func activateSelection() {
        guard let entry = model.selectedEntry else {
            note("No row selected.")
            return
        }
        guard game.inventory.runtime != nil, let container else {
            note(InventoryCore.noRuntimeText)
            return
        }
        let transfer: ContainerTransfer = switch (mode, model.side) {
        case (.container, .container): .take
        case (.container, .player): .store
        case (.barter, .container): .buy
        case (.barter, .player): .sell
        }
        do {
            try note(game.inventory.transfer(
                transfer, item: entry.item, named: entry.name, container: container, vendor: vendor
            ))
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
        guard mode == .container else {
            note("Take all is a container action, not a barter one.")
            return
        }
        note(game.inventory.takeAll(from: container))
        refreshModel()
    }

    @discardableResult
    private func note(_ text: String) -> String {
        noteAction(text)
        return text
    }

    // MARK: - Readout

    var snapshot: ContainerMenuControlSnapshot {
        let runtime = movieLoaded ? game.renderer?.swfRuntime : nil
        let diagnostics = runtime.map(ContainerMenuMovieBridge.diagnostics(runtime:))
        return ContainerMenuControlSnapshot(
            isOpen: isOpen,
            openMenus: game.menuMode.stack.identifiers.map(\.name),
            worldSimPaused: game.menuMode.isWorldSimPaused,
            mode: mode,
            side: model.side,
            transferLabel: model.transferLabel,
            containerName: containerName,
            entryLines: model.active.entries.map(InventoryMenuSection.line(for:)),
            selectedIndex: model.active.selectedIndex,
            categoryLabels: model.active.categoryLabels,
            selectedCategoryIndex: model.active.selectedCategoryIndex,
            playerGold: model.playerGold,
            containerGold: model.containerGold,
            selectedPrice: model.selectedEntry.flatMap(model.price(for:)),
            canAffordSelection: model.canAffordSelection,
            priceFactor: model.pricing.basePriceFactor,
            pricingSource: model.pricing.source,
            lastActionText: lastActionText,
            merchantOptions: merchantOptions,
            selectedMerchant: containerReference,
            movieEnabled: movieEnabled,
            movieLoaded: movieLoaded,
            movieError: movieError,
            movieDrawStats: movieLoaded
                ? (game.renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats(),
            movieFaults: diagnostics?.faults ?? 0,
            movieMissingNames: diagnostics?.missingNames ?? 0,
            movieUnhandledInvokes: diagnostics?.unhandledInvokes ?? 0,
            movieEntryTitles: runtime.map(ContainerMenuMovieBridge.entryLabels(runtime:)) ?? [],
            movieVendorGold: runtime.flatMap(ContainerMenuMovieBridge.vendorGoldText(runtime:))
        )
    }
}
