// Inventory menu (M12.2.2, issue #289): the second real `MenuInputConsumer`.
// Opening the menu pushes the engine's own menu stack, which pauses world sim
// and re-routes keyboard input here; closing pops it.
//
// AppKit and the renderer stay in this controller satellite, the row list is
// UI/InventoryMenuModel.swift, and the vanilla presentation layer is
// UI/InventoryMenuMovieBridge.swift — both build into the CLI target.
//
// The actions the menu performs are the ones World > HUD & Interaction > Items
// already performs (`equipItem`, `unequipItem`, `dropPlayerItem`), called
// through the same seam rather than reimplemented, so the menu and the panel
// cannot diverge on what equipping means. See docs/engine/inventory-menu.md.

import AppKit
import OSLog

struct InventoryMenuRuntimeState {
    var isOpen = false
    var model = InventoryMenuModel.empty
    /// Off by default, like the system menu: the engine-side row list is the
    /// durable surface, and the vanilla movie takes over the single SWF layer
    /// from the gameplay HUD.
    var movieEnabled = false
    var movieLoaded = false
    var movieError: String?
    var lastActionText: String?
}

extension GameViewController {
    static let inventoryMenuIdentifier: MenuIdentifier = "InventoryMenu"

    /// Frames the movie's own fade needs to settle after activation, measured
    /// against the install rather than guessed.
    static let inventoryMenuActivationTicks = 20

    // MARK: - Lifecycle

    func openInventoryMenuStack() {
        guard !inventoryMenu.isOpen else { return }
        inventoryMenu.isOpen = true
        refreshInventoryMenuModel()
        menuMode.inputConsumer = self
        menuMode.present(Self.inventoryMenuIdentifier)
        if inventoryMenu.movieEnabled {
            startInventoryMenuMovie()
        }
    }

    func closeInventoryMenuStack() {
        guard inventoryMenu.isOpen else { return }
        inventoryMenu.isOpen = false
        menuMode.dismiss(Self.inventoryMenuIdentifier)
        if inventoryMenu.movieLoaded {
            stopInventoryMenuMovie()
        }
    }

    /// Re-reads the player's inventory into the row list and, when the movie is
    /// up, pushes it across the bridge. Every mutation calls this, so the two
    /// lists cannot drift apart.
    func refreshInventoryMenuModel() {
        guard let inventory = worldItems.runtime?.inventory else {
            inventoryMenu.model = .empty
            return
        }
        var refreshed = InventoryMenuModel.build(holder: .player, runtime: inventory)
        refreshed.selectCategory(inventoryMenu.model.selectedCategoryIndex)
        refreshed.select(inventoryMenu.model.selectedIndex)
        inventoryMenu.model = refreshed
        publishInventoryMenuModel()
    }

    private func publishInventoryMenuModel() {
        guard inventoryMenu.movieLoaded, let renderer else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                InventoryMenuMovieBridge.publish(inventoryMenu.model, runtime: runtime)
            }
        } catch {
            inventoryMenu.movieError = String(describing: error)
        }
    }

    // MARK: - Movie

    /// Brings the vanilla movie up in place of the gameplay HUD. A missing
    /// install, an undecodable movie, or a contract the AS2 subset cannot
    /// satisfy degrades to an explanatory readout — never a thrown error out of
    /// a control action.
    func startInventoryMenuMovie() {
        guard let renderer, let loader = resolveSWFLoader() else {
            inventoryMenu.movieLoaded = false
            inventoryMenu.movieError = "No game data located."
            return
        }
        do {
            // The renderer owns exactly one SWF layer. Taking it over here is
            // the same handoff the system menu performs.
            hud.isLoaded = false
            let scene = try loader.load(path: InventoryMenuMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: InventoryMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                inventoryMenu.movieLoaded = false
                inventoryMenu.movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                InventoryMenuMovieBridge.activate(runtime: runtime) { [weak self] action in
                    self?.applyInventoryMenuAction(action)
                }
            }
            for _ in 0 ..< Self.inventoryMenuActivationTicks {
                try renderer.advanceSWFRuntime()
            }
            inventoryMenu.movieLoaded = true
            inventoryMenu.movieError = nil
            publishInventoryMenuModel()
        } catch {
            inventoryMenu.movieLoaded = false
            inventoryMenu.movieError = String(describing: error)
            Self.inventoryMenuLogger.error(
                "[ERROR] inventory menu movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Hands the SWF layer back to the gameplay HUD.
    func stopInventoryMenuMovie() {
        inventoryMenu.movieLoaded = false
        inventoryMenu.movieError = nil
        guard let renderer else { return }
        startHUD(renderer: renderer)
    }

    // MARK: - Input

    /// Navigation goes to the movie's own CLIK focus path first, and the row
    /// list follows what the movie decided. Without a movie the row list
    /// navigates itself, so the menu stays usable with no install-side movie.
    func routeInventoryMenuInput(_ event: MenuInputEvent) {
        guard inventoryMenu.isOpen else { return }
        switch event {
        case .button(.accept):
            activateInventoryMenuSelection()
            return
        case .button(.cancel):
            closeInventoryMenuStack()
            return
        case .pointer:
            return
        case let .move(direction):
            move(direction)
        }
    }

    /// Up and down move the row selection through the movie's own CLIK focus
    /// path, which owns it. Left and right change category engine-side and
    /// republish, because the movie routes those through its panel-state codes
    /// rather than through focus and nothing drives that transition without a
    /// live `InputDelegate` — measured, see docs/engine/inventory-menu.md.
    private func move(_ direction: MenuInputEvent.Direction) {
        switch direction {
        case .left, .right:
            inventoryMenu.model.moveCategory(by: direction == .right ? 1 : -1)
            publishInventoryMenuModel()
        case .up, .down:
            guard !driveMovie(direction) else { return }
            inventoryMenu.model.moveSelection(by: direction == .down ? 1 : -1)
            publishInventoryMenuModel()
        }
    }

    /// Sends the key through the movie's CLIK path and reads the resulting
    /// selection back. Returns false when there is no movie to drive, or when
    /// the movie declined the key.
    private func driveMovie(_ direction: MenuInputEvent.Direction) -> Bool {
        guard inventoryMenu.movieLoaded, let renderer else { return false }
        do {
            let consumed = try InventoryMenuMovieBridge.send(
                .move(direction), renderer: renderer
            )
            guard consumed, let runtime = renderer.swfRuntime else { return false }
            // The movie's list is authoritative for where a key landed, so the
            // engine's own move above is a prediction the movie corrects.
            if let index = InventoryMenuMovieBridge.selectedCategoryIndex(runtime: runtime) {
                inventoryMenu.model.selectCategory(index)
            }
            if let index = InventoryMenuMovieBridge.selectedIndex(runtime: runtime) {
                inventoryMenu.model.select(index)
            }
            publishInventoryMenuModel()
            return true
        } catch {
            inventoryMenu.movieError = String(describing: error)
            return false
        }
    }

    // MARK: - Actions

    private func applyInventoryMenuAction(_ action: InventoryMenuAction) {
        switch action {
        case .close:
            closeInventoryMenuStack()
        case let .equip(index):
            inventoryMenu.model.select(index)
            activateInventoryMenuSelection()
        case let .drop(index):
            inventoryMenu.model.select(index)
            dropInventoryMenuSelection()
        }
    }

    private static let inventoryMenuLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "InventoryMenu"
    )
}

extension GameViewController: InventoryMenuControlProviding {
    var inventoryMenuIsOpen: Bool {
        inventoryMenu.isOpen
    }

    var inventoryMenuMovieEnabled: Bool {
        get { inventoryMenu.movieEnabled }
        set {
            guard newValue != inventoryMenu.movieEnabled else { return }
            inventoryMenu.movieEnabled = newValue
            guard inventoryMenu.isOpen else { return }
            if newValue {
                startInventoryMenuMovie()
            } else {
                stopInventoryMenuMovie()
            }
        }
    }

    func openInventoryMenu() {
        openInventoryMenuStack()
    }

    func closeInventoryMenu() {
        closeInventoryMenuStack()
    }

    func sendInventoryMenuInput(_ event: MenuInputEvent) {
        routeInventoryMenuInput(event)
    }

    /// Equip toggles: activating an equipped row unequips it. That is what the
    /// vanilla menu does, and a separate unequip control would need the player
    /// to know which state a row is in before pressing anything.
    func activateInventoryMenuSelection() {
        guard let entry = inventoryMenu.model.selectedEntry else {
            inventoryMenu.lastActionText = "No row selected."
            return
        }
        inventoryMenu.lastActionText = entry.isEquipped
            ? unequipItem(entry.item, on: .player)
            : equipItem(entry.item, on: .player)
        refreshInventoryMenuModel()
    }

    func dropInventoryMenuSelection() {
        guard let entry = inventoryMenu.model.selectedEntry else {
            inventoryMenu.lastActionText = "No row selected."
            return
        }
        inventoryMenu.lastActionText = dropPlayerItem(entry.item, count: 1)
        refreshInventoryMenuModel()
    }

    func consumeInventoryMenuSelection() {
        guard let entry = inventoryMenu.model.selectedEntry else {
            inventoryMenu.lastActionText = "No row selected."
            return
        }
        inventoryMenu.lastActionText = consumeMagicItem(entry.item)
        refreshInventoryMenuModel()
    }

    var inventoryMenuSnapshot: InventoryMenuControlSnapshot {
        let model = inventoryMenu.model
        let runtime = inventoryMenu.movieLoaded ? renderer?.swfRuntime : nil
        let diagnostics = runtime.map(InventoryMenuMovieBridge.diagnostics(runtime:))
        return InventoryMenuControlSnapshot(
            isOpen: inventoryMenu.isOpen,
            openMenus: menuMode.stack.identifiers.map(\.name),
            worldSimPaused: menuMode.isWorldSimPaused,
            categoryLabels: model.categoryLabels,
            selectedCategoryIndex: model.selectedCategoryIndex,
            entryLines: model.entries.map(InventoryMenuSection.line(for:)),
            selectedIndex: model.selectedIndex,
            carriedWeight: model.carriedWeight,
            gold: model.gold,
            lastActionText: inventoryMenu.lastActionText,
            movieEnabled: inventoryMenu.movieEnabled,
            movieLoaded: inventoryMenu.movieLoaded,
            movieError: inventoryMenu.movieError,
            movieDrawStats: inventoryMenu.movieLoaded
                ? (renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats(),
            movieFaults: diagnostics?.faults ?? 0,
            movieMissingNames: diagnostics?.missingNames ?? 0,
            movieUnhandledInvokes: diagnostics?.unhandledInvokes ?? 0,
            movieEntryTitles: runtime.map(InventoryMenuMovieBridge.entryLabels(runtime:)) ?? [],
            movieCategoryTitles: runtime
                .map(InventoryMenuMovieBridge.categoryLabels(runtime:)) ?? []
        )
    }
}
