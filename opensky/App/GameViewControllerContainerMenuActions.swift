// Transactions, merchant nomination and the panel snapshot for the container
// and barter menus (M12.2.3, issue #179). Satellite of
// GameViewControllerContainerMenu.swift, which owns the lifecycle and the
// movie.
//
// Every refusal a transaction can produce — an empty chest, a player who cannot
// pay, a merchant with no gold — lands in `lastActionText` and leaves the world
// untouched. A menu that throws out of a button action would be a worse answer
// than one that says why it did nothing.

import AppKit

extension GameViewController: ContainerMenuControlProviding {
    var containerMenuIsOpen: Bool {
        containerMenu.isOpen
    }

    /// Switching mode swaps which vanilla movie is up, because the container
    /// and barter menus are two movies rather than two states of one. An open
    /// menu is closed and reopened so the menu-stack identifier matches.
    var containerMenuMode: ContainerMenuModel.Mode {
        get { containerMenu.mode }
        set {
            guard newValue != containerMenu.mode else { return }
            let wasOpen = containerMenu.isOpen
            closeContainerMenuStack()
            containerMenu.mode = newValue
            if wasOpen {
                openContainerMenuStack()
            }
        }
    }

    var containerMenuMovieEnabled: Bool {
        get { containerMenu.movieEnabled }
        set {
            guard newValue != containerMenu.movieEnabled else { return }
            containerMenu.movieEnabled = newValue
            guard containerMenu.isOpen else { return }
            if newValue {
                startContainerMenuMovie()
            } else {
                stopContainerMenuMovie()
            }
        }
    }

    func openContainerMenu() {
        openContainerMenuStack()
    }

    func closeContainerMenu() {
        closeContainerMenuStack()
    }

    func sendContainerMenuInput(_ event: MenuInputEvent) {
        routeContainerMenuInput(event)
    }

    func switchContainerMenuSide() {
        containerMenu.model.switchSide()
        refreshContainerMenuModel()
    }

    // MARK: - Merchant nomination

    var containerMenuMerchantOptions: [ContainerMenuMerchantOption] {
        guard let inventory = worldItems.runtime?.inventory else { return [] }
        return (streamer?.containerInteractions() ?? []).compactMap { interaction in
            guard let holder = holder(for: interaction) else { return nil }
            return ContainerMenuMerchantOption(
                reference: interaction.reference,
                name: interaction.name,
                itemCount: Int(inventory.inventory(of: holder).totalCount),
                gold: inventory.goldCount(of: holder)
            )
        }
    }

    @discardableResult
    func selectContainerMenuMerchant(_ reference: FormID) -> String {
        guard let streamer else {
            return refuseNomination("no cell is loaded")
        }
        guard
            let interaction = streamer.containerInteractions()
                .first(where: { $0.reference == reference })
        else {
            return refuseNomination("\(reference) is not a resident container")
        }
        return nominate(interaction)
    }

    @discardableResult
    func selectContainerMenuMerchantFromInteraction() -> String {
        guard let interaction = currentInteraction, interaction.action == .search else {
            return refuseNomination("the crosshair is not on a container")
        }
        return nominate(interaction)
    }

    private func nominate(_ interaction: PlacedInteraction) -> String {
        guard nominateContainerMenuMerchant(interaction) else {
            return refuseNomination("world items are unavailable, or nothing resident holds it")
        }
        containerMenu.lastActionText = "Merchant: \(interaction.name)."
        refreshContainerMenuModel()
        return containerMenu.lastActionText ?? ""
    }

    private func refuseNomination(_ reason: String) -> String {
        containerMenu.lastActionText = "Cannot nominate a merchant: \(reason)."
        return containerMenu.lastActionText ?? ""
    }

    /// Binds one container interaction to the menu as its active target.
    ///
    /// The holder carries the reference key, the CONT base its baseline is
    /// re-derived from, and the cell the mutations are attributed to — the same
    /// three `WorldItemRuntime.openContainer` builds, resolved the same way, so
    /// a chest opened from the crosshair and one nominated from the sidebar are
    /// the same owner.
    @discardableResult
    func nominateContainerMenuMerchant(_ interaction: PlacedInteraction) -> Bool {
        guard worldItems.runtime != nil, let holder = holder(for: interaction) else {
            return false
        }
        containerMenu.container = holder
        containerMenu.containerName = interaction.name
        containerMenu.containerReference = interaction.reference
        return true
    }

    /// Nil when nothing resident resolves the reference: a `ReferenceKey` comes
    /// from the runtime index, and fabricating one would attribute the
    /// merchant's stock to a key nothing else in the world agrees with.
    private func holder(for interaction: PlacedInteraction) -> InventoryHolder? {
        guard let entry = streamer?.referenceEntry(formID: interaction.reference) else {
            return nil
        }
        return InventoryHolder(
            key: entry.key,
            owner: .container(base: interaction.base),
            cell: streamer?.cellLocation(of: entry.key)
        )
    }

    // MARK: - Transactions

    /// Take, store, buy or sell, according to the mode and the side.
    func activateContainerMenuSelection() {
        guard let entry = containerMenu.model.selectedEntry else {
            containerMenu.lastActionText = "No row selected."
            return
        }
        guard let runtime = worldItems.runtime, let container = containerMenu.container else {
            containerMenu.lastActionText = "World items unavailable: no game data loaded."
            return
        }
        containerMenu.lastActionText = transfer(entry, container: container, runtime: runtime)
        refreshContainerMenuModel()
    }

    private func transfer(
        _ entry: InventoryMenuEntry,
        container: InventoryHolder,
        runtime: WorldItemRuntime
    ) -> String {
        do {
            switch (containerMenu.mode, containerMenu.model.side) {
            case (.container, .container):
                // Through the session rather than straight to `transfer`, so a
                // single-row take marks and reports theft exactly as "take all"
                // does (issue #504). Two controls over the same act must not
                // disagree about whether it is a crime.
                let bounty = try ContainerSession(runtime: runtime, container: container)
                    .take(entry.item)
                return bounty > 0
                    ? "Stole \(entry.name) — \(bounty) bounty."
                    : "Took \(entry.name)."
            case (.container, .player):
                try runtime.inventory.transfer(entry.item, count: 1, from: .player, to: container)
                return "Stored \(entry.name)."
            case (.barter, .container):
                let bought = try barterSession(container: container, runtime: runtime)
                    .buy(entry.item)
                return "Bought \(entry.name) for \(bought.gold) gold."
            case (.barter, .player):
                let sold = try barterSession(container: container, runtime: runtime)
                    .sell(entry.item)
                return "Sold \(entry.name) for \(sold.gold) gold."
            }
        } catch {
            return "\(containerMenu.model.transferLabel) refused: \(String(describing: error))"
        }
    }

    /// A fresh session per transaction rather than one held open: the session
    /// caches nothing, and building it here means a merchant re-nominated
    /// mid-menu cannot leave a stale one behind.
    private func barterSession(
        container: InventoryHolder,
        runtime: WorldItemRuntime
    ) -> BarterSession {
        BarterSession(runtime: runtime, merchant: container, pricing: containerMenuPricing)
    }

    func takeAllFromContainerMenu() {
        guard let runtime = worldItems.runtime, let container = containerMenu.container else {
            containerMenu.lastActionText = "World items unavailable: no game data loaded."
            return
        }
        guard containerMenu.mode == .container else {
            containerMenu.lastActionText = "Take all is a container action, not a barter one."
            return
        }
        let session = ContainerSession(runtime: runtime, container: container)
        do {
            let moved = try session.takeAll()
            let total = moved.reduce(0) { $0 + Int($1.count) }
            containerMenu.lastActionText =
                "Took all: \(total) items in \(moved.count) stacks."
        } catch {
            containerMenu.lastActionText = "Take all failed: \(String(describing: error))"
        }
        refreshContainerMenuModel()
    }

    // MARK: - Readout

    var containerMenuSnapshot: ContainerMenuControlSnapshot {
        let model = containerMenu.model
        let runtime = containerMenu.movieLoaded ? renderer?.swfRuntime : nil
        let diagnostics = runtime.map(ContainerMenuMovieBridge.diagnostics(runtime:))
        let entry = model.selectedEntry
        return ContainerMenuControlSnapshot(
            isOpen: containerMenu.isOpen,
            openMenus: menuMode.stack.identifiers.map(\.name),
            worldSimPaused: menuMode.isWorldSimPaused,
            mode: containerMenu.mode,
            side: model.side,
            transferLabel: model.transferLabel,
            containerName: containerMenu.containerName,
            entryLines: model.active.entries.map(InventoryMenuSection.line(for:)),
            selectedIndex: model.active.selectedIndex,
            categoryLabels: model.active.categoryLabels,
            selectedCategoryIndex: model.active.selectedCategoryIndex,
            playerGold: model.playerGold,
            containerGold: model.containerGold,
            selectedPrice: entry.flatMap(model.price(for:)),
            canAffordSelection: model.canAffordSelection,
            priceFactor: model.pricing.basePriceFactor,
            pricingSource: model.pricing.source,
            lastActionText: containerMenu.lastActionText,
            merchantOptions: containerMenuMerchantOptions,
            selectedMerchant: containerMenu.containerReference,
            movieEnabled: containerMenu.movieEnabled,
            movieLoaded: containerMenu.movieLoaded,
            movieError: containerMenu.movieError,
            movieDrawStats: containerMenu.movieLoaded
                ? (renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats(),
            movieFaults: diagnostics?.faults ?? 0,
            movieMissingNames: diagnostics?.missingNames ?? 0,
            movieUnhandledInvokes: diagnostics?.unhandledInvokes ?? 0,
            movieEntryTitles: runtime.map(ContainerMenuMovieBridge.entryLabels(runtime:)) ?? [],
            movieVendorGold: runtime.flatMap(ContainerMenuMovieBridge.vendorGoldText(runtime:))
        )
    }
}
