// Routes menu keys and pointer events to the menu on top of the stack, and wires
// the settings, menu text, sounds, and frame tick that every menu movie shares.

import AppKit
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyWorld

/// What `MenuRouter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuRouterHost: MenuSoundHost, SystemMenuWorld {
    var containerMenu: ContainerMenuController { get }
    var controlMapLoader: (() throws -> ControlMapFile)? { get }
    var dialogueMenu: DialogueMenuController { get }
    var inventoryMenu: InventoryMenuController { get }
    var journalMenu: JournalMenuController { get }
    var lockpickingMenu: LockpickingMenuController { get }
    var mapMenu: MapMenuCoordinator { get }
    var mapWorld: MapWorldAdapter { get }
    var menuMode: MenuModeController { get }
    var menuTextLoader: (() -> LocalizedLabels)? { get }
    var menuScreens: MenuScreens { get }
    var menuWorld: MenuWorldAdapter { get }
    var messages: MessageCoordinator { get }
    var movies: MoviePlayerCoordinator { get }
    var titleSequence: TitleSequenceCoordinator { get }
    var mounts: MountCoordinator { get }
    var playerSettings: PlayerSettingsCoordinator { get }
    var raceMenu: RaceMenuCoordinator { get }
    var saveGames: SaveGameWorldAdapter { get }
    var skillsMenu: SkillsMenuCoordinator { get }
    var systemMenu: SystemMenuCoordinator { get }
    var titleMenu: TitleMenuCoordinator { get }
    var hostView: NSView { get }
}

final class MenuRouter {
    unowned let game: any MenuRouterHost
    let gamepads = GamepadMonitor()

    init(game: any MenuRouterHost) {
        self.game = game
    }

    /// The bound keys that open a menu or save, outside any menu.
    func run(_ action: GameInputAction) {
        switch action {
        case .map:
            game.mapMenu.open()
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
        gamepads.onDisconnect = { [weak game] in
            guard let game else { return }
            let texts = game.mapWorld.settingTexts(GamepadNoticeText.self)
            game.messages.presentChoices(
                title: texts[.title], text: texts[.message], buttons: [texts[.confirm]]
            ) { _ in }
        }
        let sounds = MenuSoundPlayer(MenuSoundDependencies(game: game))
        renderer.swfSoundPlayer = { sounds.play(editorID: $0 ?? MenuSoundPlayer.okSound) }
        gameSession.frameSteps.register(.menuRouting) { [weak game, weak renderer, gamepads] _ in
            game?.mapMenu.tick()
            let now = Date().timeIntervalSinceReferenceDate
            if let game, let renderer {
                gamepads.poll(now: now, renderer: renderer, menuMode: game.menuMode)
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
        table.register(LoadingScreenWorldAdapter.identifier) { _ in }
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
        game.menuScreens.register(in: table)
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
