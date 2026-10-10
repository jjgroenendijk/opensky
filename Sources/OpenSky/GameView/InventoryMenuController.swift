// The inventory menu: opening it pushes the menu stack, which pauses world sim
// and routes keyboard input here. The row list is `InventoryMenuModel`, the
// vanilla movie is `InventoryMenuMovieBridge`, and every action calls the same
// `InventoryCoordinator` method the Items panel calls.
// See docs/engine/inventory-menu.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyRendering

/// Holds the inventory menu's row list and movie state for `game`.
final class InventoryMenuController {
    static let identifier: MenuIdentifier = "InventoryMenu"
    /// Frames the movie's own fade needs to settle, measured on the install.
    static let activationTicks = 20

    unowned let game: GameViewController
    private(set) var isOpen = false
    private(set) var model = InventoryMenuModel.empty
    /// On by default, so play mode draws the menu. The HUD is suspended while
    /// the movie holds the single SWF layer.
    private(set) var movieEnabled = true
    private(set) var movieLoaded = false
    /// Bumped by each open and close, so a movie decoded late opens only the newest.
    private var movieRequest = 0
    private(set) var movieError: String?
    private(set) var lastActionText: String?

    init(game: GameViewController) {
        self.game = game
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
        game.menuMode.dismiss(Self.identifier)
        if movieLoaded {
            stopMovie()
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

    /// Re-reads the player's inventory. Every change calls this, so the row
    /// list and the movie cannot drift apart.
    func refreshModel() {
        guard let inventory = game.inventory.runtime?.inventory else {
            model = .empty
            return
        }
        var refreshed = InventoryMenuModel.build(holder: .player, runtime: inventory)
        refreshed.selectCategory(model.selectedCategoryIndex)
        refreshed.select(model.selectedIndex)
        model = refreshed
        publishModel()
    }

    private func publishModel() {
        guard movieLoaded, let renderer = game.renderer else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                InventoryMenuMovieBridge.publish(model, runtime: runtime)
            }
        } catch {
            movieError = String(describing: error)
        }
    }

    // MARK: - Movie

    /// Brings the vanilla movie up in place of the gameplay HUD. Any failure
    /// becomes a readout, never a thrown error out of a control action.
    private func startMovie() {
        guard game.renderer != nil, game.swfMovies.isAvailable else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        game.hud.suspend()
        movieRequest += 1
        let request = movieRequest
        game.swfMovies.request(InventoryMenuMovieBridge.moviePath, while: { [weak self] in
            self?.movieRequest == request
        }, then: { [weak self] result in
            self?.showMovie(result)
        })
    }

    /// Runs when the movie is decoded, which may be a later frame than the open.
    private func showMovie(_ result: Result<SWFMovieScene, AssetLoadFailure>) {
        guard let renderer = game.renderer else { return }
        do {
            try renderer.setSWFMovie(result.get())
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: InventoryMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                movieLoaded = false
                movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                InventoryMenuMovieBridge.activate(runtime: runtime) { [weak self] action in
                    self?.apply(action)
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
                "[ERROR] inventory menu movie: \(String(describing: error), privacy: .public)"
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

    /// Without a movie the row list moves itself, so the menu works with no
    /// install-side movie.
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

    /// Left and right change category here, because the movie routes them
    /// through panel-state codes that nothing drives without a live
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
        guard movieLoaded, let renderer = game.renderer else { return false }
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
            movieError = String(describing: error)
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
            dropSelection()
        }
    }

    /// Activating an equipped row unequips it, as the vanilla menu does.
    func activateSelection() {
        perform { entry in
            entry.isEquipped
                ? game.inventory.unequipItem(entry.item, on: .player)
                : game.inventory.equipItem(entry.item, on: .player)
        }
    }

    func dropSelection() {
        perform { game.inventory.dropPlayerItem($0.item, count: 1) }
    }

    func consumeSelection() {
        perform { game.magic.consumeMagicItem($0.item) }
    }

    private func perform(_ action: (InventoryMenuEntry) -> String) {
        guard let entry = model.selectedEntry else {
            lastActionText = "No row selected."
            return
        }
        lastActionText = action(entry)
        refreshModel()
    }

    // MARK: - Readout

    var snapshot: InventoryMenuControlSnapshot {
        let runtime = movieLoaded ? game.renderer?.swfRuntime : nil
        let diagnostics = runtime.map(InventoryMenuMovieBridge.diagnostics(runtime:))
        return InventoryMenuControlSnapshot(
            isOpen: isOpen,
            openMenus: game.menuMode.stack.identifiers.map(\.name),
            worldSimPaused: game.menuMode.isWorldSimPaused,
            categoryLabels: model.categoryLabels,
            selectedCategoryIndex: model.selectedCategoryIndex,
            entryLines: model.entries.map(InventoryMenuSection.line(for:)),
            selectedIndex: model.selectedIndex,
            carriedWeight: model.carriedWeight,
            gold: model.gold,
            lastActionText: lastActionText,
            enchantmentLines: game.inventory.equippedReadout(on: .player)
                .compactMap { readout in
                    readout.enchantment.map { "\(readout.name) — \($0)" }
                },
            movieEnabled: movieEnabled,
            movieLoaded: movieLoaded,
            movieError: movieError,
            movieDrawStats: movieLoaded
                ? (game.renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats(),
            movieFaults: diagnostics?.faults ?? 0,
            movieMissingNames: diagnostics?.missingNames ?? 0,
            movieUnhandledInvokes: diagnostics?.unhandledInvokes ?? 0,
            movieEntryTitles: runtime.map(InventoryMenuMovieBridge.entryLabels(runtime:)) ?? [],
            movieCategoryTitles: runtime
                .map(InventoryMenuMovieBridge.categoryLabels(runtime:)) ?? []
        )
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "InventoryMenu"
    )
}
