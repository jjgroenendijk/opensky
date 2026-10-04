// The container and barter menus: two vanilla movies over one two-pane list.
// The list is `ContainerMenuModel`, the movies are `ContainerMenuMovieBridge`,
// and every transaction is an `InventoryCoordinator` call.
// See docs/engine/barter.md.

import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorldInterface
import OSLog

/// Holds the container menu's target, list and movie state for `game`.
final class ContainerMenuController {
    static let containerIdentifier: MenuIdentifier = "ContainerMenu"
    static let barterIdentifier: MenuIdentifier = "BarterMenu"
    /// Frames the movie's fade needs to settle, the same as `inventorymenu.swf`.
    static let activationTicks = 20

    unowned let game: GameViewController
    private(set) var isOpen = false
    private(set) var mode = ContainerMenuModel.Mode.container
    private(set) var model = ContainerMenuModel.empty
    /// Nominated for barter, or taken from the crosshair for a container.
    private(set) var container: InventoryHolder?
    private(set) var containerName: String?
    /// Kept beside the holder, because a `ReferenceKey` does not carry the
    /// FormID the merchant popup selects by.
    private(set) var containerReference: FormID?
    /// Nil for a nominated or looted container, which trades anything.
    private(set) var vendor: Vendor?
    /// Off by default: the vanilla movie takes the single SWF layer from the
    /// gameplay HUD.
    private(set) var movieEnabled = false
    private(set) var movieLoaded = false
    /// Bumped by each open and close, so a movie decoded late opens only the newest.
    private var movieRequest = 0
    private(set) var movieError: String?
    private(set) var lastActionText: String?

    init(game: GameViewController) {
        self.game = game
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
            lastActionText = "No container selected. Look at one, or nominate a merchant."
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
        game.menuMode.dismiss(activeIdentifier)
        if movieLoaded {
            stopMovie()
        }
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

    func setMovieEnabled(_ enabled: Bool) {
        guard enabled != movieEnabled else { return }
        movieEnabled = enabled
        guard isOpen else { return }
        if enabled {
            startMovie()
        } else {
            stopMovie()
        }
    }

    /// Binds the menu to `holder`. `vendor` is nil for a plain container.
    func target(
        _ holder: InventoryHolder,
        name: String,
        reference: FormID?,
        vendor: Vendor? = nil
    ) {
        container = holder
        containerName = name
        containerReference = reference
        self.vendor = vendor
    }

    func noteAction(_ text: String) {
        lastActionText = text
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
            pricing: game.inventory.barterPricing,
            runtime: inventory
        )
        refreshed.restore(from: model)
        model = refreshed
        publishModel()
    }

    func switchSide() {
        model.switchSide()
        refreshModel()
    }

    private func publishModel() {
        guard movieLoaded, let renderer = game.renderer else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                ContainerMenuMovieBridge.publish(model, runtime: runtime)
            }
        } catch {
            movieError = String(describing: error)
        }
    }

    // MARK: - Movie

    /// Brings the mode's vanilla movie up in place of the gameplay HUD. Any
    /// failure becomes a readout, never a thrown error out of a control action.
    private func startMovie() {
        guard game.renderer != nil, game.swfMovies.isAvailable else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        game.hud.suspend()
        movieRequest += 1
        let request = movieRequest
        game.swfMovies.request(
            ContainerMenuMovieBridge.moviePath(for: mode),
            while: { [weak self] in
                self?.movieRequest == request
            },
            then: { [weak self] result in
                self?.showMovie(result)
            }
        )
    }

    /// Runs when the movie is decoded, which may be a later frame than the open.
    private func showMovie(_ result: Result<SWFMovieScene, AssetLoadFailure>) {
        guard let renderer = game.renderer else { return }
        do {
            try renderer.setSWFMovie(result.get())
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: ContainerMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                movieLoaded = false
                movieError = "SWF runtime unavailable."
                return
            }
            let mode = mode
            try renderer.updateSWFRuntime { runtime in
                ContainerMenuMovieBridge.activate(runtime: runtime, mode: mode) { [weak self] in
                    self?.apply($0)
                }
            }
            for _ in 0 ..< Self.activationTicks {
                try renderer.advanceSWFRuntime()
            }
            movieLoaded = true
            movieError = nil
            publishModel()
        } catch {
            movieLoaded = false
            movieError = String(describing: error)
            Self.logger.error(
                "[ERROR] container menu movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Hands the SWF layer back to the gameplay HUD.
    private func stopMovie() {
        movieRequest += 1
        movieLoaded = false
        movieError = nil
        game.hud.start()
    }

    // MARK: - Input

    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        switch event {
        case .button(.accept):
            activateSelection()
        case .button(.cancel):
            close()
        case .pointer, .release:
            return
        case let .move(direction):
            move(direction)
        }
    }

    /// Left and right swap sides, because the horizontal axis of a two-pane
    /// menu picks the owner. Category still moves through the panel.
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
        guard movieLoaded, let renderer = game.renderer else { return false }
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
            movieError = String(describing: error)
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
        lastActionText = entry.isEquipped
            ? game.inventory.unequipItem(entry.item, on: .player)
            : game.inventory.equipItem(entry.item, on: .player)
        refreshModel()
    }

    static let logger = Logger(subsystem: "nl.jjgroenendijk.opensky", category: "ContainerMenu")
}
