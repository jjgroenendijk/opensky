// Routes menu keys and pointer events to the menu on top of the stack, and wires
// the settings, menu text, sounds, and frame tick that every menu movie shares.

import AppKit
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld

final class MenuRouter {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    func makeSystemMenu() -> SystemMenuCoordinator {
        let menu = SystemMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud
        )
        menu.attach(world: game)
        menu.attach(settings: game.playerSettings)
        menu.saves = game.saveGames
        return menu
    }

    func makeTitleMenu() -> TitleMenuCoordinator {
        let menu = TitleMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud
        )
        menu.attach(world: game.menuWorld)
        menu.saves = game.saveGames
        return menu
    }

    func makeRaceMenu() -> RaceMenuCoordinator {
        let menu = RaceMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud
        )
        menu.attach(world: game.menuWorld)
        return menu
    }

    func makeSkillsMenu() -> SkillsMenuCoordinator {
        let menu = SkillsMenuCoordinator(
            menuMode: game.menuMode,
            movies: game.swfMovies,
            hud: game.hud
        )
        menu.attach(world: game.menuWorld)
        return menu
    }

    func makeMapMenu() -> MapMenuCoordinator {
        let menu = MapMenuCoordinator(menuMode: game.menuMode)
        menu.attach(world: game.mapWorld)
        return menu
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
    func wire(renderer: Renderer) {
        game.playerSettings.loadControlMap(try? game.controlMapLoader?())
        game.playerSettings.attach(world: game.menuWorld)
        game.audio.onEngineBuilt = { [weak game] in game?.playerSettings.applyAll() }
        if let labels = game.menuTextLoader?() {
            renderer.swfTextTranslator = { labels.label(for: $0) }
        }
        let sounds = MenuSoundPlayer(MenuSoundDependencies(game: game))
        renderer.swfSoundPlayer = { sounds.play(editorID: $0 ?? MenuSoundPlayer.okSound) }
        renderer.session.frameSteps.register(.menuRouting) { [weak game] _ in
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
        (game.view as? GameMetalView)?.setMenuCursorFree(free)
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
