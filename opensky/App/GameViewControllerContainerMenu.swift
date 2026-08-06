// Container and barter menus (M12.2.3, issue #179): the third and fourth real
// `MenuInputConsumer`s, and the first that moves gold.
//
// AppKit and the renderer stay in this controller satellite; the two-pane list
// is UI/ContainerMenuModel.swift, the vanilla presentation layer is
// UI/ContainerMenuMovieBridge.swift, and the transactions are
// Inventory/BarterSession.swift — all three build into the CLI target.
//
// The transfers are #177's `ContainerSession` and #176's accounting, called
// through rather than reimplemented, so the menu and the World > HUD &
// Interaction > Items panel cannot diverge about what taking an item means.
//
// See docs/engine/barter.md.

import AppKit
import OSLog

struct ContainerMenuRuntimeState {
    var isOpen = false
    var mode = ContainerMenuModel.Mode.container
    var model = ContainerMenuModel.empty
    /// The container this session is against, nominated for barter and taken
    /// from the crosshair for a plain container.
    var container: InventoryHolder?
    var containerName: String?
    /// The nominated container's reference FormID. Kept beside the holder
    /// because a `ReferenceKey` does not carry one back, and the panel's popup
    /// selects by FormID.
    var containerReference: FormID?
    /// Off by default, like the other two menus: the engine-side list is the
    /// durable surface, and the vanilla movie takes the single SWF layer from
    /// the gameplay HUD.
    var movieEnabled = false
    var movieLoaded = false
    var movieError: String?
    var lastActionText: String?
}

extension GameViewController {
    static let containerMenuIdentifier: MenuIdentifier = "ContainerMenu"
    static let barterMenuIdentifier: MenuIdentifier = "BarterMenu"
    /// Frames the movie's own fade needs to settle, the same count
    /// `inventorymenu.swf` needs.
    static let containerMenuActivationTicks = 20

    /// Which stack identifier this session is presenting under, which follows
    /// the mode because the two modes are two movies.
    var activeContainerMenuIdentifier: MenuIdentifier {
        containerMenu.mode == .barter ? Self.barterMenuIdentifier : Self.containerMenuIdentifier
    }

    // MARK: - Lifecycle

    /// Opens the menu on the nominated container, or on whatever container the
    /// crosshair is pointing at when nothing is nominated yet.
    func openContainerMenuStack() {
        guard !containerMenu.isOpen else { return }
        guard resolveContainerMenuTarget() else {
            containerMenu.lastActionText =
                "No container selected. Look at one, or nominate a merchant."
            return
        }
        containerMenu.isOpen = true
        refreshContainerMenuModel()
        menuMode.inputConsumer = self
        menuMode.present(activeContainerMenuIdentifier)
        if containerMenu.movieEnabled {
            startContainerMenuMovie()
        }
    }

    func closeContainerMenuStack() {
        guard containerMenu.isOpen else { return }
        containerMenu.isOpen = false
        menuMode.dismiss(activeContainerMenuIdentifier)
        if containerMenu.movieLoaded {
            stopContainerMenuMovie()
        }
    }

    /// A nominated merchant wins; otherwise the crosshair's container becomes
    /// the target, which is what opening a chest in front of you does.
    private func resolveContainerMenuTarget() -> Bool {
        if containerMenu.container != nil {
            return true
        }
        guard let interaction = currentInteraction, interaction.action == .search else {
            return false
        }
        return nominateContainerMenuMerchant(interaction)
    }

    /// Re-reads both inventories and, when the movie is up, pushes them across
    /// the bridge. Every transaction calls this, so the two lists cannot drift.
    func refreshContainerMenuModel() {
        guard
            let inventory = worldItems.runtime?.inventory,
            let container = containerMenu.container
        else {
            containerMenu.model = .empty
            return
        }
        var refreshed = ContainerMenuModel.build(
            container: container,
            containerName: containerMenu.containerName ?? "Container",
            mode: containerMenu.mode,
            pricing: containerMenuPricing,
            runtime: inventory
        )
        refreshed.restore(from: containerMenu.model)
        containerMenu.model = refreshed
        publishContainerMenuModel()
    }

    /// The load order's own `fBarterMin` and `fBarterMax`, or the documented
    /// vanilla defaults on a synthetic scene with no plugins behind it.
    var containerMenuPricing: BarterPricing {
        worldItems.barterPricing
    }

    private func publishContainerMenuModel() {
        guard containerMenu.movieLoaded, let renderer else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                ContainerMenuMovieBridge.publish(containerMenu.model, runtime: runtime)
            }
        } catch {
            containerMenu.movieError = String(describing: error)
        }
    }

    // MARK: - Movie

    /// Brings the mode's vanilla movie up in place of the gameplay HUD. A
    /// missing install or an unsatisfiable contract degrades to an explanatory
    /// readout, never a thrown error out of a control action.
    func startContainerMenuMovie() {
        guard let renderer, let loader = resolveSWFLoader() else {
            containerMenu.movieLoaded = false
            containerMenu.movieError = "No game data located."
            return
        }
        do {
            hud.isLoaded = false
            let path = ContainerMenuMovieBridge.moviePath(for: containerMenu.mode)
            try renderer.setSWFMovie(loader.load(path: path))
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: ContainerMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                containerMenu.movieLoaded = false
                containerMenu.movieError = "SWF runtime unavailable."
                return
            }
            let mode = containerMenu.mode
            try renderer.updateSWFRuntime { runtime in
                ContainerMenuMovieBridge.activate(runtime: runtime, mode: mode) { [weak self] in
                    self?.applyContainerMenuAction($0)
                }
            }
            for _ in 0 ..< Self.containerMenuActivationTicks {
                try renderer.advanceSWFRuntime()
            }
            containerMenu.movieLoaded = true
            containerMenu.movieError = nil
            publishContainerMenuModel()
        } catch {
            containerMenu.movieLoaded = false
            containerMenu.movieError = String(describing: error)
            Self.containerMenuLogger.error(
                "[ERROR] container menu movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Hands the SWF layer back to the gameplay HUD.
    func stopContainerMenuMovie() {
        containerMenu.movieLoaded = false
        containerMenu.movieError = nil
        guard let renderer else { return }
        startHUD(renderer: renderer)
    }

    // MARK: - Input

    func routeContainerMenuInput(_ event: MenuInputEvent) {
        guard containerMenu.isOpen else { return }
        switch event {
        case .button(.accept):
            activateContainerMenuSelection()
        case .button(.cancel):
            closeContainerMenuStack()
        case .pointer:
            return
        case let .move(direction):
            move(direction)
        }
    }

    /// Left and right swap sides here rather than changing category, because
    /// swapping which owner you are looking at is what a two-pane menu's
    /// horizontal axis means. Category still moves through the panel.
    private func move(_ direction: MenuInputEvent.Direction) {
        switch direction {
        case .left, .right:
            switchContainerMenuSide()
        case .up, .down:
            guard !driveMovie(direction) else { return }
            containerMenu.model.moveSelection(by: direction == .down ? 1 : -1)
            publishContainerMenuModel()
        }
    }

    private func driveMovie(_ direction: MenuInputEvent.Direction) -> Bool {
        guard containerMenu.movieLoaded, let renderer else { return false }
        do {
            let consumed = try ContainerMenuMovieBridge.send(.move(direction), renderer: renderer)
            guard consumed, let runtime = renderer.swfRuntime else { return false }
            // The movie's list owns where a key landed, so the engine's own
            // move is a prediction the movie corrects.
            if let index = ContainerMenuMovieBridge.selectedIndex(runtime: runtime) {
                containerMenu.model.select(index)
            }
            publishContainerMenuModel()
            return true
        } catch {
            containerMenu.movieError = String(describing: error)
            return false
        }
    }

    private func applyContainerMenuAction(_ action: ContainerMenuAction) {
        switch action {
        case .close:
            closeContainerMenuStack()
        case let .transfer(index):
            containerMenu.model.select(index)
            activateContainerMenuSelection()
        case .takeAll:
            takeAllFromContainerMenu()
        case let .equip(index):
            containerMenu.model.select(index)
            equipContainerMenuSelection()
        }
    }

    private func equipContainerMenuSelection() {
        guard let entry = containerMenu.model.selectedEntry else { return }
        containerMenu.lastActionText = entry.isEquipped
            ? unequipItem(entry.item, on: .player)
            : equipItem(entry.item, on: .player)
        refreshContainerMenuModel()
    }

    static let containerMenuLogger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "ContainerMenu"
    )
}
