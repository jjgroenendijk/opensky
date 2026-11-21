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
    /// The movie's own quantity slider is open, so keys go to the movie.
    var movieQuantityOpen = false
    /// The movie's last `UpdateItem3D`: whether its item list shows the 3D item.
    var movieShowsItem3D = false
    /// Set by a movie answer to `DropItem`, so a drop the movie ignored falls back.
    var movieAnsweredDrop = false

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
        movieQuantityOpen = false
        movieShowsItem3D = false
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
        refreshed.hide(game.inventory.scriptItems.hiddenItems)
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
            didLoad: { [weak self] in
                // The movie opens on its category list; right or accept opens the rows.
                self?.publishModel()
            }
        ))
    }

    // MARK: - Input

    /// Without a movie the row list moves itself, so the menu works with no
    /// install-side movie.
    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if movieQuantityOpen {
            routeMovieQuantity(event)
            return
        }
        if model.quantity != nil {
            routeQuantity(event)
            return
        }
        switch event {
        case .button(.cancel):
            close()
        case .pointer, .release, .activate:
            return
        case let .move(direction):
            move(direction)
        case .button(.accept) where !showsItems:
            move(.right)
        case .button:
            guard showsItems else { return }
            routeItemKey(event)
        }
    }

    /// The row keys, which act only while the item panel shows.
    private func routeItemKey(_ event: MenuInputEvent) {
        switch event {
        case .button(.accept):
            activateSelection()
        case .button(.xButton):
            requestDrop()
        case .button(.yButton):
            toggleFavouriteSelection()
        case .button(.leftEquip):
            perform { itemActions.useInLeftHand($0.item) }
        default:
            return
        }
    }

    /// True with no movie, whose row list is always shown.
    private var showsItems: Bool {
        guard let runtime = movie.loadedRenderer?.swfRuntime else { return true }
        return InventoryMenuMovieBridge.showsItems(runtime: runtime)
    }

    /// The movie moves its own focus and lists. With no movie, left and right
    /// change category here.
    private func move(_ direction: MenuInputEvent.Direction) {
        if let renderer = movie.loadedRenderer {
            driveMovie(direction, renderer: renderer)
            return
        }
        switch direction {
        case .left, .right:
            model.moveCategory(by: direction == .right ? 1 : -1)
            publishModel()
        case .up, .down:
            model.moveSelection(by: direction == .down ? 1 : -1)
            publishModel()
        }
    }

    /// A key the movie declines, such as right on the open rows, does nothing.
    private func driveMovie(_ direction: MenuInputEvent.Direction, renderer: any RendererPort) {
        guard let runtime = renderer.swfRuntime else { return }
        do {
            let moved = try InventoryMenuMovieBridge.navigate(
                direction, model: &model, runtime: runtime
            ) { try InventoryMenuMovieBridge.send($0, renderer: renderer) }
            if moved {
                publishModel()
            }
        } catch {
            movie.record(error)
        }
    }

    // MARK: - Actions

    private func apply(_ action: InventoryMenuAction) {
        switch action {
        case .close:
            close()
        case .equipSelected:
            activateSelection()
        case let .drop(count):
            movieAnsweredDrop = true
            movieQuantityOpen = false
            dropSelection(count: Int32(clamping: count))
        case let .quantitySlider(open):
            movieAnsweredDrop = movieAnsweredDrop || open
            movieQuantityOpen = open
        case let .item3D(visible):
            movieShowsItem3D = visible
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
