// The inventory menu: opening it pushes the menu stack, which pauses world sim
// and routes keyboard input here. The row list is `InventoryMenuModel`, the
// vanilla movie is `InventoryMenuMovieBridge`, and every action calls the same
// `InventoryCoordinator` method the Items readout calls.
// See docs/engine/inventory-menu.md.

import Foundation
import OpenSkyCells
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld

/// What `InventoryMenuController` reads from the session. `GameViewController` conforms.
@MainActor
protocol InventoryMenuHost: MenuInputConsumer, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    var worldData: WorldDataStores? { get }
    var mapWorld: any MapWorldPort { get }
    var magic: any MagicPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var combat: any CombatPort { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var menuMode: any MenuModePort { get }
    var menuScreens: any MenuScreensPort { get }
    var renderer: (any RendererPort)? { get }
    var swfMovies: any SWFMovieSourcePort { get }
}

/// Holds the inventory menu's row list and movie state for `game`.
final class InventoryMenuController {
    static let identifier = MenuIdentifier.inventoryMenu
    /// Frames the movie's own fade needs to settle, measured on the install.
    static let activationTicks = 20

    unowned let game: any InventoryMenuHost
    let itemDetails: InventoryMenuItemDetails
    private(set) var isOpen = false
    var model = InventoryMenuModel.empty
    /// On by default, so play mode draws the menu. The HUD is suspended while
    /// the movie holds the single SWF layer.
    private(set) var movieEnabled = true
    var lastActionText: String?
    let movie: MenuMovieSession
    /// The turning item beside the list. Off leaves the world behind the menu bare.
    var previewEnabled = true
    var preview = InventoryItemPreview()
    var previewSource: InventoryItemPreviewSource?
    var previewShown = false

    init(game: any InventoryMenuHost, itemDetails: InventoryMenuItemDetails) {
        self.game = game
        self.itemDetails = itemDetails
        movie = MenuMovieSession(
            movies: game.swfMovies, hud: game.hud, label: "inventory menu movie",
            logger: Self.logger
        ) { [unowned game] in game.renderer }
    }

    // MARK: - Lifecycle

    func open() {
        guard !isOpen else { return }
        isOpen = true
        refreshModel()
        game.menuMode.inputConsumer = game
        game.menuMode.present(Self.identifier)
        if movieEnabled {
            startMovie()
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        model.quantity = nil
        game.menuMode.dismiss(Self.identifier)
        movie.stop()
        hidePreview()
    }

    /// Re-reads the player's inventory. Every change calls this, so the row
    /// list and the movie cannot drift apart.
    func refreshModel() {
        guard let inventory = game.inventory.runtime?.inventory else {
            model = .empty
            return
        }
        var refreshed = InventoryMenuModel.build(
            holder: .player, runtime: inventory,
            categories: InventoryMenuCategory.tabs(
                texts: itemDetails.menuTexts, favourites: true
            ),
            favourites: game.inventory.favouriteItems.playerFavourites
        )
        refreshed.carriedWeight = game.inventory.armourWeights.playerCarriedWeight
        refreshed.markQuestItems(game.inventory.scriptItems.questItems)
        if !model.categories.isEmpty {
            refreshed.selectCategory(model.selectedCategoryIndex)
            refreshed.select(model.selectedIndex)
        }
        refreshed.quantity = model.quantity
        model = refreshed
        publishModel()
    }

    private func publishModel() {
        let model = model
        let item = model.selectedEntry?.item
        let card = itemDetails.card(for: item)
        let charge = itemDetails.chargePercent(of: item)
        movie.publish {
            InventoryMenuMovieBridge.publish(model, runtime: $0)
            InventoryMenuMovieBridge.publishItemCard(card, charge: charge, runtime: $0)
        }
    }

    // MARK: - Movie

    /// Brings the vanilla movie up in place of the gameplay HUD.
    private func startMovie() {
        movie.start(MenuMovie(
            path: InventoryMenuMovieBridge.moviePath,
            activationTicks: Self.activationTicks,
            prepare: InventoryMenuMovieBridge.prepare(runtime:),
            activate: { [weak self] runtime in
                InventoryMenuMovieBridge.activate(runtime: runtime) { [weak self] action in
                    self?.apply(action)
                }
            },
            didLoad: { [weak self] in self?.publishModel() }
        ))
    }

    // MARK: - Input

    /// Without a movie the row list moves itself, so the menu works with no
    /// install-side movie.
    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if model.quantity != nil {
            routeQuantity(event)
            return
        }
        switch event {
        case .button(.accept):
            activateSelection()
        case .button(.cancel):
            close()
        case .button(.xButton):
            requestDrop()
        case .button(.yButton):
            toggleFavouriteSelection()
        case .pointer, .release:
            return
        case let .move(direction):
            move(direction)
        }
    }

    /// Left and right change category here, because the movie routes them
    /// through readout-state codes that nothing drives without a live
    /// `InputDelegate` (docs/engine/inventory-menu.md).
    private func move(_ direction: MenuInputEvent.Direction) {
        switch direction {
        case .left, .right:
            model.moveCategory(by: direction == .right ? 1 : -1)
            publishModel()
        case .up, .down:
            guard !driveMovie(direction) else { return }
            model.moveSelection(by: direction == .down ? 1 : -1)
            publishModel()
        }
    }

    /// False when there is no movie, or the movie declined the key.
    private func driveMovie(_ direction: MenuInputEvent.Direction) -> Bool {
        guard let renderer = movie.loadedRenderer else { return false }
        do {
            let consumed = try InventoryMenuMovieBridge.send(.move(direction), renderer: renderer)
            guard consumed, let runtime = renderer.swfRuntime else { return false }
            // The movie's list decides where a key landed.
            if let index = InventoryMenuMovieBridge.selectedCategoryIndex(runtime: runtime) {
                model.selectCategory(index)
            }
            if let index = InventoryMenuMovieBridge.selectedIndex(runtime: runtime) {
                model.select(index)
            }
            publishModel()
            return true
        } catch {
            movie.record(error)
            return false
        }
    }

    // MARK: - Actions

    private func apply(_ action: InventoryMenuAction) {
        switch action {
        case .close:
            close()
        case let .equip(index):
            model.select(index)
            activateSelection()
        case let .drop(index):
            model.select(index)
            requestDrop()
        case .showSoulGems:
            showSoulGems()
        case let .chooseCardListEntry(index):
            chooseSoulGem(index)
        }
    }

    /// Activating an equipped row unequips it, as the vanilla menu does. A book opens;
    /// the inventory closes first, because both draw on the one movie layer.
    func activateSelection() {
        let books = game.menuScreens.book
        if let entry = model.selectedEntry, books.isBook(entry.item) {
            close()
            books.open(item: entry.item)
            return
        }
        if let entry = model.selectedEntry, askBeforePoison(entry) {
            return
        }
        perform { itemActions.use($0.item) }
    }

    /// A poison the weapon can take asks first; Yes puts it on.
    private func askBeforePoison(_ entry: InventoryMenuEntry) -> Bool {
        let item = entry.item
        guard
            let question = itemDetails.poisonQuestion(
                item, refusal: itemActions.refusal(.consume, of: item)
            )
        else { return false }
        itemDetails.ask(question) { [weak self] yes in
            guard let self, yes, isOpen, model.selectedEntry?.item == item else { return }
            perform { itemActions.use($0.item) }
        }
        lastActionText = question
        return true
    }

    func dropSelection(count: Int32 = 1) {
        perform { entry in
            itemActions.refusal(.drop, of: entry.item)
                ?? game.inventory.itemActions.dropPlayerItem(entry.item, count: count).text
        }
    }

    func perform(_ action: (InventoryMenuEntry) -> String) {
        guard let entry = model.selectedEntry else {
            lastActionText = "No row selected."
            return
        }
        lastActionText = action(entry)
        refreshModel()
    }

    // MARK: - Readout

    var snapshot: InventoryMenuControlSnapshot {
        InventoryMenuControlSnapshot(
            entryLines: model.entries.map(\.readoutLine),
            selectedIndex: model.selectedIndex
        )
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "InventoryMenu"
    )
}
