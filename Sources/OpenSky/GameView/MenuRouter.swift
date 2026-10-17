// Routes menu keys and pointer events to the menu on top of the stack, and wires
// the settings, menu text, sounds, and frame tick that every menu movie shares.

import AppKit
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld

/// What `MenuRouter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuRouterHost: MenuSoundHost, SystemMenuWorld {
    var containerMenu: ContainerMenuController { get }
    var controlMapLoader: (() throws -> ControlMapFile)? { get }
    var dialogueMenu: DialogueMenuController { get }
    var hud: HUDCoordinator { get }
    var inventoryMenu: InventoryMenuController { get }
    var journalMenu: JournalMenuController { get }
    var lockpickingMenu: LockpickingMenuController { get }
    var mapMenu: MapMenuCoordinator { get }
    var mapWorld: MapWorldAdapter { get }
    var menuMode: MenuModeController { get }
    var menuTextLoader: (() -> LocalizedLabels)? { get }
    var menuWorld: MenuWorldAdapter { get }
    var messages: MessageCoordinator { get }
    var playerSettings: PlayerSettingsCoordinator { get }
    var raceMenu: RaceMenuCoordinator { get }
    var saveGames: SaveGameWorldAdapter { get }
    var skillsMenu: SkillsMenuCoordinator { get }
    var swfMovies: SWFMovieSource { get }
    var systemMenu: SystemMenuCoordinator { get }
    var titleMenu: TitleMenuCoordinator { get }
    var hostView: NSView { get }
}

final class MenuRouter {
    unowned let game: any MenuRouterHost

    init(game: any MenuRouterHost) {
        self.game = game
    }

    func makeSystemMenu() -> SystemMenuCoordinator {
        let menu = SystemMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud,
            world: game
        )
        menu.attach(settings: game.playerSettings)
        menu.saves = game.saveGames
        return menu
    }

    func makeTitleMenu() -> TitleMenuCoordinator {
        let menu = TitleMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud,
            world: game.menuWorld
        )
        menu.saves = game.saveGames
        return menu
    }

    func makeRaceMenu() -> RaceMenuCoordinator {
        RaceMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud,
            world: game.menuWorld
        )
    }

    func makeSkillsMenu() -> SkillsMenuCoordinator {
        SkillsMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud,
            world: game.menuWorld
        )
    }

    func makeMapMenu() -> MapMenuCoordinator {
        MapMenuCoordinator(menuMode: game.menuMode, world: game.mapWorld)
    }

    /// The bound keys that open a menu or save, outside any menu.
    func run(_ action: GameInputAction) {
        switch action {
        case .map:
            game.mapMenu.open()
        case .skills:
            game.skillsMenu.open()
        case .quicksave:
            game.systemMenu.quicksave()
        case .quickload:
            game.saveGames.quickload()
        case .pause:
            game.saveGames.autosave(.pause)
            game.systemMenu.open()
        default:
            return
        }
    }

    /// Settings, key bindings, menu text, the menu natives, map discovery, and
    /// the menu movies' late calls.
    func wire(gameSession: GameSession) {
        let renderer = gameSession.renderer
        game.playerSettings.loadControlMap(try? game.controlMapLoader?())
        game.playerSettings.applyAll()
        game.audio.onEngineBuilt = { [weak game] in game?.playerSettings.applyAll() }
        if let labels = game.menuTextLoader?() {
            renderer.swfTextTranslator = { labels.label(for: $0) }
        }
        let sounds = MenuSoundPlayer(MenuSoundDependencies(game: game))
        renderer.swfSoundPlayer = { sounds.play(editorID: $0 ?? MenuSoundPlayer.okSound) }
        gameSession.frameSteps.register(.menuRouting) { [weak game] _ in
            game?.mapMenu.tick()
            let now = Date().timeIntervalSinceReferenceDate
            game?.titleMenu.tick(now: now)
            game?.raceMenu.tick(now: now)
            game?.skillsMenu.tick(now: now)
            game?.systemMenu.tick(now: now)
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
        table
            .register(TitleMenuCoordinator.identifier) { [unowned game] in
                game.titleMenu.route($0)
            }
        table.register(RaceMenuCoordinator.identifier) { [unowned game] in game.raceMenu.route($0) }
        table.register(MapMenuCoordinator.identifier) { [unowned game] in game.mapMenu.route($0) }
        table.register(SkillsMenuCoordinator.identifier) { [unowned game] in
            game.skillsMenu.route($0)
        }
        return table
    }()

    /// The menus whose movie hit tests the cursor, so it must be visible.
    static let cursorMenus: [MenuIdentifier] = [
        TitleMenuCoordinator.identifier, RaceMenuCoordinator.identifier
    ]

    /// A script opens the race menu during play, while look holds the cursor.
    func modeChanged(to route: InputRoute) {
        let free = route == .menu && game.menuMode.topMenu.map(Self.cursorMenus.contains) == true
        (game.hostView as? GameMetalView)?.setMenuCursorFree(free)
    }

    /// The main menu movie hit tests the cursor. The other menus still take a
    /// press as their accept button.
    func route(_ event: MenuPointerEvent) {
        if game.menuMode.topMenu == TitleMenuCoordinator.identifier {
            game.titleMenu.route(event)
        } else if game.menuMode.topMenu == RaceMenuCoordinator.identifier {
            game.raceMenu.route(event)
        } else if event.phase == .pressed {
            route(.button(.accept))
        }
    }
}
