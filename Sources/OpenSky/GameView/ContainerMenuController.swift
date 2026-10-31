// The container and barter menus: two vanilla movies over one two-pane list.
// The list is `ContainerMenuModel`, the movies are `ContainerMenuMovieBridge`,
// and every transaction is an `InventoryCoordinator` call.
// See docs/engine/barter.md.

import Foundation
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `ContainerMenuController` reads from the session. `GameViewController` conforms.
@MainActor
protocol ContainerMenuHost: MenuInputConsumer {
    var dialogueMenu: DialogueMenuController { get }
    var dialogueWorld: DialogueWorldAdapter { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var mapWorld: MapWorldAdapter { get }
    var menuMode: MenuModeController { get }
    var ragdoll: RagdollCoordinator { get }
    var renderer: Renderer? { get }
    var streamer: CellStreamer? { get }
    var swfMovies: SWFMovieSource { get }
}

/// Holds the container menu's target, list and movie state for `game`.
final class ContainerMenuController {
    static let containerIdentifier: MenuIdentifier = "ContainerMenu"
    static let barterIdentifier: MenuIdentifier = "BarterMenu"
    /// Frames the movie's fade needs to settle, the same as `inventorymenu.swf`.
    static let activationTicks = 20

    unowned let game: any ContainerMenuHost
    private(set) var isOpen = false
    private(set) var mode = ContainerMenuModel.Mode.container
    private(set) var model = ContainerMenuModel.empty
    /// Nominated for barter, or taken from the crosshair for a container.
    private(set) var container: InventoryHolder?
    private(set) var containerName: String?
    /// Nil for a nominated or looted container, which trades anything.
    private(set) var vendor: Vendor?
    /// The actor the player barters with, whom the price perks name.
    private(set) var merchant: ReferenceKey?
    /// The living actor whose pockets are open. Each take then rolls the chance.
    var pickpocketTarget: ReferenceKey?
    /// The follower whose own items are open, which keeps its outfit and carry weight.
    var teammateTarget: ReferenceKey?
    /// Whether a take from the open pockets succeeded, so "Pockets Picked" counts once.
    var pickedOpenPockets = false
    /// The count slider a stack of more than five opens before it moves.
    var quantity: InventoryQuantityPrompt?
    /// A sale the merchant cannot pay in full, waiting for accept or cancel.
    var pendingSale: (entry: InventoryMenuEntry, count: Int32)?
    /// On by default, so play mode draws the menu. The HUD is suspended while
    /// the movie holds the single SWF layer.
    private(set) var movieEnabled = true
    let movie: MenuMovieSession

    init(game: any ContainerMenuHost) {
        self.game = game
        movie = MenuMovieSession(
            movies: game.swfMovies, hud: game.hud, label: "container menu movie",
            logger: Self.logger
        ) { [unowned game] in game.renderer }
    }

    /// The two modes are two movies, so each has its own stack identifier.
    var activeIdentifier: MenuIdentifier {
        mode == .barter ? Self.barterIdentifier : Self.containerIdentifier
    }

    // MARK: - Lifecycle

    /// Opens on the nominated container, else on the crosshair's container,
    /// else on the nearest corpse.
    func open() {
        guard !isOpen else { return }
        guard resolveTarget() else {
            noteAction("No container selected. Look at one, or nominate a merchant.")
            return
        }
        isOpen = true
        refreshModel()
        game.menuMode.inputConsumer = game
        game.menuMode.present(activeIdentifier)
        if movieEnabled {
            startMovie()
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        quantity = nil
        pendingSale = nil
        game.menuMode.dismiss(activeIdentifier)
        movie.stop()
    }

    /// An open menu closes and reopens, so the stack identifier matches.
    func setMode(_ newMode: ContainerMenuModel.Mode) {
        guard newMode != mode else { return }
        let wasOpen = isOpen
        close()
        mode = newMode
        if wasOpen {
            open()
        }
    }

    /// Binds the menu to `holder`. `vendor` is nil for a plain container.
    func target(
        _ holder: InventoryHolder,
        name: String,
        vendor: Vendor? = nil,
        merchant: ReferenceKey? = nil
    ) {
        container = holder
        pickpocketTarget = nil
        teammateTarget = nil
        pickedOpenPockets = false
        containerName = name
        self.vendor = vendor
        self.merchant = merchant
    }

    /// The vanilla menus show no action line, so the outcome goes to the log.
    func noteAction(_ text: String) {
        Self.logger.info("\(text, privacy: .public)")
    }

    private func resolveTarget() -> Bool {
        if container != nil {
            return true
        }
        if
            let interaction = game.hud.interactionTarget?.interaction,
            interaction.action == .search
        {
            return nominate(interaction)
        }
        return game.ragdoll.searchNearestCorpse()
    }

    /// Re-reads both inventories. Every transaction calls this, so the list and
    /// the movie cannot drift.
    func refreshModel() {
        guard let inventory = game.inventory.runtime?.inventory, let container else {
            model = .empty
            return
        }
        var refreshed = ContainerMenuModel.build(
            container: container,
            containerName: containerName ?? "Container",
            mode: mode,
            pricing: game.inventory.barterPricing(with: merchant),
            runtime: inventory,
            categories: InventoryMenuCategory.tabs(texts: game.inventory.menuTexts)
        )
        refreshed.player.carriedWeight = game.inventory.playerCarriedWeight
        if teammateTarget != nil {
            refreshed.container = refreshed.container
                .hiding(game.inventory.teammateOutfit(of: container))
        }
        refreshed.restore(from: model)
        model = refreshed
        publishModel()
    }

    func switchSide() {
        model.switchSide()
        refreshModel()
    }

    private func publishModel() {
        let model = model
        movie.publish { ContainerMenuMovieBridge.publish(model, runtime: $0) }
    }

    // MARK: - Movie

    /// Brings the mode's vanilla movie up in place of the gameplay HUD.
    private func startMovie() {
        let mode = mode
        movie.start(MenuMovie(
            path: ContainerMenuMovieBridge.moviePath(for: mode),
            activationTicks: Self.activationTicks,
            prepare: ContainerMenuMovieBridge.prepare(runtime:),
            activate: { [weak self] runtime in
                ContainerMenuMovieBridge.activate(runtime: runtime, mode: mode) { [weak self] in
                    self?.apply($0)
                }
            },
            didLoad: { [weak self] in self?.publishModel() }
        ))
    }

    // MARK: - Input

    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if quantity != nil || pendingSale != nil {
            routePrompt(event)
            return
        }
        switch event {
        case .button(.accept):
            activateSelection()
        case .button(.cancel):
            close()
        case .button(.xButton), .button(.yButton), .pointer, .release:
            return
        case let .move(direction):
            move(direction)
        }
    }

    /// Left and right swap sides, because the horizontal axis of a two-pane
    /// menu picks the owner. Category still moves through the readout.
    private func move(_ direction: MenuInputEvent.Direction) {
        switch direction {
        case .left, .right:
            switchSide()
        case .up, .down:
            guard !driveMovie(direction) else { return }
            model.moveSelection(by: direction == .down ? 1 : -1)
            publishModel()
        }
    }

    private func driveMovie(_ direction: MenuInputEvent.Direction) -> Bool {
        guard let renderer = movie.loadedRenderer else { return false }
        do {
            let consumed = try ContainerMenuMovieBridge.send(.move(direction), renderer: renderer)
            guard consumed, let runtime = renderer.swfRuntime else { return false }
            // The movie's list decides where a key landed.
            if let index = ContainerMenuMovieBridge.selectedIndex(runtime: runtime) {
                model.select(index)
            }
            publishModel()
            return true
        } catch {
            movie.record(error)
            return false
        }
    }

    private func apply(_ action: ContainerMenuAction) {
        switch action {
        case .close:
            close()
        case let .transfer(index):
            model.select(index)
            activateSelection()
        case .takeAll:
            takeAll()
        case let .equip(index):
            model.select(index)
            equipSelection()
        }
    }

    private func equipSelection() {
        guard let entry = model.selectedEntry else { return }
        noteAction(entry.isEquipped
            ? game.inventoryWorld.run(game.inventory.unequipItem(entry.item, on: .player)).text
            : game.inventoryWorld.run(game.inventory.equipItem(entry.item, on: .player)).text)
        refreshModel()
    }

    static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "ContainerMenu"
    )
}
