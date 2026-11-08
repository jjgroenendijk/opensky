// Routes menu keys and pointer events to the menu on top of the stack, and wires
// the settings, menu text, sounds, and frame tick that every menu movie shares.

import AppKit
import OpenSkyAIPackages
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `MenuRouter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuRouterHost: MenuSoundHost, SystemMenuWorld {
    var containerMenu: any ContainerMenuPort { get }
    var controlMapLoader: (() throws -> ControlMapFile)? { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var followerCommands: any FollowerCommandPort { get }
    var inventoryMenu: any InventoryMenuPort { get }
    var journalMenu: any JournalMenuPort { get }
    var loadingWorld: any LoadingScreenWorldPort { get }
    var lockpickingMenu: any LockpickingMenuPort { get }
    var mapMenu: any MapMenuPort { get }
    var mapWorld: any MapWorldPort { get }
    var menuMode: any MenuModePort { get }
    var menuTextLoader: (() -> any LocalizedLabelsPort)? { get }
    var menuScreens: any MenuScreensPort { get }
    var menuWorld: any MenuWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var movies: any MoviePlayerPort { get }
    var titleSequence: any TitleSequencePort { get }
    var mounts: any MountPort { get }
    var playerSettings: any PlayerSettingsPort { get }
    var raceMenu: any RaceMenuPort { get }
    var saveGames: any SaveGameWorldPort { get }
    var skillsMenu: any SkillsMenuPort { get }
    var systemMenu: any SystemMenuPort { get }
    var titleMenu: any TitleMenuPort { get }
    var hostView: NSView { get }
}

final class MenuRouter {
    unowned let game: any MenuRouterHost
    private let monitor = GamepadMonitor()
    var gamepads: any GamepadMonitorPort {
        monitor
    }

    init(game: any MenuRouterHost) {
        self.game = game
    }

    /// The bound keys that open a menu or save, outside any menu, and the map's own keys.
    func run(_ action: GameInputAction) {
        switch action {
        case .map:
            game.mapMenu.open()
        case .placeMarker:
            game.mapMenu.placePlayerMarker()
        case .skills:
            game.skillsMenu.open()
        case .wait:
            game.menuScreens.sleepWait.open(sleeping: false)
        case .magic:
            game.menuScreens.magic.open()
        case .quicksave:
            game.systemMenu.quicksave()
        case .quickload:
            game.saveGames.quickload()
        case .pause:
            // In command mode the key only leaves it, as Tab does in the game.
            guard !game.followerCommands.cancel() else { return }
            game.saveGames.autosave(.pause)
            game.systemMenu.open()
        default:
            guard let slot = action.hotkeySlot else { return }
            // On a flying dragon, 1 and 2 switch the target (UESP "Skyrim:Controls").
            if slot <= 2, game.mounts.switchDragonTarget(forward: slot == 2) {
                return
            }
            game.inventoryMenu.useHotkey(slot)
        }
    }

    /// Settings, key bindings, menu text, the menu natives, map discovery, and
    /// the menu movies' late calls.
    func wire(gameSession: GameSession) {
        let renderer = gameSession.renderer
        game.playerSettings.loadControlMap(try? game.controlMapLoader?())
        game.playerSettings.applyAll()
        game.audio.engineStarted
            .register(.playerSettings) { [weak game] _ in game?.playerSettings.applyAll() }
        if let labels = game.menuTextLoader?() {
            renderer.swfTextTranslator = { labels.label(for: $0) }
        }
        monitor.onDisconnect = { [weak game] in
            guard let game else { return }
            let texts = game.mapWorld.settingTexts(GamepadNoticeText.self)
            game.messages.presentChoices(
                title: texts[.title], text: texts[.message], buttons: [texts[.confirm]]
            ) { _ in }
        }
        let sounds = MenuSoundPlayer(MenuSoundDependencies(game: game))
        renderer.swfSoundPlayer = { sounds.play(editorID: $0 ?? MenuSoundPlayer.okSound) }
        gameSession.frameSteps.register(.menuRouting) { [weak game, weak renderer, monitor] _ in
            game?.mapMenu.tick()
            let now = Date().timeIntervalSinceReferenceDate
            if let game, let renderer {
                monitor.poll(now: now, renderer: renderer, menuMode: game.menuMode)
            }
            game?.movies.tick(now: now)
            game?.titleSequence.tick()
            game?.titleMenu.tick(now: now)
            game?.raceMenu.tick(now: now)
            game?.skillsMenu.tick(now: now)
            game?.systemMenu.tick(now: now)
            game?.menuScreens.tick(now: now)
            game?.inventoryMenu.tick(now: now)
            game?.menuWorld.refreshTitleBackdrop()
        }
    }

    /// The one menu input consumer routes by the top of the menu stack. Each
    /// route checks that its own menu is open.
    func route(_ event: MenuInputEvent) {
        routes.route(event, top: game.menuMode.topMenu)
    }

    private lazy var routes: MenuRouteTable = {
        let table = MenuRouteTable { [unowned game] in game.systemMenu.route($0) }
        table.register(InventoryMenuController.identifier) { [unowned game] in
            game.inventoryMenu.route($0)
        }
        table.register(
            ContainerMenuController.containerIdentifier, ContainerMenuController.barterIdentifier
        ) { [unowned game] in game.containerMenu.route($0) }
        table.register(JournalMenuController.identifier) { [unowned game] in
            game.journalMenu.route($0)
        }
        table.register(DialogueMenuController.identifier) { [unowned game] in
            game.dialogueMenu.route($0)
        }
        table.register(LockpickingMenuController.identifier) { [unowned game] in
            game.lockpickingMenu.route($0)
        }
        table.register(MessageCoordinator.identifier) { [unowned game] in game.messages.route($0) }
        table.register(LoadingScreenWorldAdapter.identifier) { [unowned game] in
            game.loadingWorld.route($0)
        }
        table.register(MoviePlayerCoordinator.identifier) { [unowned game] in
            game.movies.route($0)
        }
        table
            .register(TitleMenuCoordinator.identifier) { [unowned game] in
                game.titleMenu.route($0)
            }
        table.register(RaceMenuCoordinator.identifier) { [unowned game] in game.raceMenu.route($0) }
        table.register(MapMenuCoordinator.identifier) { [unowned game] in game.mapMenu.route($0) }
        table.register(SkillsMenuCoordinator.identifier) { [unowned game] in
            game.skillsMenu.route($0)
        }
        for (identifier, route) in game.menuScreens.keyRoutes {
            table.register(identifier, route: route)
        }
        return table
    }()

    /// The menus whose movie hit tests the cursor, so it must be visible.
    static let cursorMenus: [MenuIdentifier] = [
        TitleMenuCoordinator.identifier, RaceMenuCoordinator.identifier,
        MessageCoordinator.identifier
    ] + MenuScreens.cursorMenus

    /// A script opens the race menu during play, while look holds the cursor.
    func modeChanged(to route: InputRoute) {
        let free = route == .menu && game.menuMode.topMenu.map(Self.cursorMenus.contains) == true
        (game.hostView as? GameMetalView)?.setMenuCursorFree(free)
    }

    /// A menu whose movie hit tests the cursor gets it. The other menus take a
    /// press as their accept button.
    func route(_ event: MenuPointerEvent) {
        if let route = game.menuMode.topMenu.flatMap({ pointerRoutes[$0] }) {
            route(event)
        } else if event.phase == .pressed {
            route(.button(.accept))
        }
    }

    /// The menus whose movie takes the cursor itself.
    private var pointerRoutes: [MenuIdentifier: (MenuPointerEvent) -> Void] {
        [
            TitleMenuCoordinator.identifier: { [unowned game] in game.titleMenu.route($0) },
            RaceMenuCoordinator.identifier: { [unowned game] in game.raceMenu.route($0) },
            MessageCoordinator.identifier: { [unowned game] in game.messages.route($0) }
        ].merging(game.menuScreens.pointerRoutes) { first, _ in first }
    }
}
