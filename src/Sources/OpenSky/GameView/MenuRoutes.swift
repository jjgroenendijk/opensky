// The parts of `MenuRouter` that each reach a few menus: the bound keys that open a
// menu, the per-frame menu tick, and the tables that send input to the top menu.

import Foundation
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorldInterface

/// The menus the bound keys open outside any menu.
@MainActor
protocol MenuHotkeyHost: AnyObject, SendableMetatype {
    var followerCommands: any FollowerCommandPort { get }
    var inventoryMenu: any InventoryMenuPort { get }
    var mapMenu: any MapMenuPort { get }
    var menuScreens: any MenuScreensPort { get }
    var mounts: any MountPort { get }
    var saveGames: any SaveGameWorldPort { get }
    var skillsMenu: any SkillsMenuPort { get }
    var systemMenu: any SystemMenuPort { get }
}

/// The menus that advance their movies each frame.
@MainActor
protocol MenuTickHost: AnyObject, SendableMetatype {
    var inventoryMenu: any InventoryMenuPort { get }
    var mapMenu: any MapMenuPort { get }
    var menuMode: any MenuModePort { get }
    var menuScreens: any MenuScreensPort { get }
    var menuWorld: any MenuWorldPort { get }
    var movies: any MoviePlayerPort { get }
    var raceMenu: any RaceMenuPort { get }
    var skillsMenu: any SkillsMenuPort { get }
    var systemMenu: any SystemMenuPort { get }
    var titleMenu: any TitleMenuPort { get }
    var titleSequence: any TitleSequencePort { get }
}

/// The menus opened during play, which take keys only.
@MainActor
protocol MenuPlayRoutesHost: AnyObject, SendableMetatype {
    var containerMenu: any ContainerMenuPort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var inventoryMenu: any InventoryMenuPort { get }
    var journalMenu: any JournalMenuPort { get }
    var loadingWorld: any LoadingScreenWorldPort { get }
    var lockpickingMenu: any LockpickingMenuPort { get }
    var messages: any MessageCoordinatorPort { get }
}

/// The menu stack, and the menus of the title and pause screens.
@MainActor
protocol MenuFrontRoutesHost: AnyObject, SendableMetatype {
    var mapMenu: any MapMenuPort { get }
    var menuMode: any MenuModePort { get }
    var menuScreens: any MenuScreensPort { get }
    var messages: any MessageCoordinatorPort { get }
    var movies: any MoviePlayerPort { get }
    var raceMenu: any RaceMenuPort { get }
    var skillsMenu: any SkillsMenuPort { get }
    var systemMenu: any SystemMenuPort { get }
    var titleMenu: any TitleMenuPort { get }
}

typealias MenuRouteHosts = MenuFrontRoutesHost & MenuPlayRoutesHost

/// The bound keys that open a menu or save, outside any menu, and the map's own keys.
struct MenuHotkeys {
    unowned let game: any MenuHotkeyHost

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
            useHotkey(action)
        }
    }

    private func useHotkey(_ action: GameInputAction) {
        guard let slot = action.hotkeySlot else { return }
        // On a flying dragon, 1 and 2 switch the target (UESP "Skyrim:Controls").
        if slot <= 2, game.mounts.switchDragonTarget(forward: slot == 2) {
            return
        }
        game.inventoryMenu.useHotkey(slot)
    }
}

/// Polls the gamepads and advances every menu movie once a frame.
struct MenuFrameTick {
    unowned let game: any MenuTickHost

    func tick(renderer: Renderer?, monitor: GamepadMonitor) {
        game.mapMenu.tick()
        let now = Date().timeIntervalSinceReferenceDate
        if let renderer {
            monitor.poll(now: now, renderer: renderer, menuMode: game.menuMode)
        }
        game.movies.tick(now: now)
        game.titleSequence.tick()
        game.titleMenu.tick(now: now)
        game.raceMenu.tick(now: now)
        game.skillsMenu.tick(now: now)
        game.systemMenu.tick(now: now)
        game.menuScreens.tick(now: now)
        game.inventoryMenu.tick(now: now)
        game.menuWorld.refreshTitleBackdrop()
    }
}

/// Builds the tables that send menu input to the menu on top of the stack.
struct MenuRoutes {
    unowned let play: any MenuPlayRoutesHost
    unowned let front: any MenuFrontRoutesHost

    func keyTable() -> MenuRouteTable {
        let table = MenuRouteTable { [unowned front] in front.systemMenu.route($0) }
        addPlayRoutes(to: table)
        addFrontRoutes(to: table)
        for (identifier, route) in front.menuScreens.keyRoutes {
            table.register(identifier, route: route)
        }
        return table
    }

    func pointerTable() -> [MenuIdentifier: (MenuPointerEvent) -> Void] {
        [
            TitleMenuCoordinator.identifier: { [unowned front] in front.titleMenu.route($0) },
            RaceMenuCoordinator.identifier: { [unowned front] in front.raceMenu.route($0) },
            MessageCoordinator.identifier: { [unowned front] in front.messages.route($0) }
        ].merging(front.menuScreens.pointerRoutes) { first, _ in first }
    }

    private func addPlayRoutes(to table: MenuRouteTable) {
        table.register(InventoryMenuController.identifier) { [unowned play] in
            play.inventoryMenu.route($0)
        }
        table.register(
            ContainerMenuController.containerIdentifier, ContainerMenuController.barterIdentifier
        ) { [unowned play] in play.containerMenu.route($0) }
        table.register(JournalMenuController.identifier) { [unowned play] in
            play.journalMenu.route($0)
        }
        table.register(DialogueMenuController.identifier) { [unowned play] in
            play.dialogueMenu.route($0)
        }
        table.register(LockpickingMenuController.identifier) { [unowned play] in
            play.lockpickingMenu.route($0)
        }
        table.register(MessageCoordinator.identifier) { [unowned play] in play.messages.route($0) }
        table.register(LoadingScreenWorldAdapter.identifier) { [unowned play] in
            play.loadingWorld.route($0)
        }
    }

    private func addFrontRoutes(to table: MenuRouteTable) {
        table.register(MoviePlayerCoordinator.identifier) { [unowned front] in
            front.movies.route($0)
        }
        table.register(TitleMenuCoordinator.identifier) { [unowned front] in
            front.titleMenu.route($0)
        }
        table
            .register(RaceMenuCoordinator.identifier) { [unowned front] in
                front.raceMenu.route($0)
            }
        table.register(MapMenuCoordinator.identifier) { [unowned front] in front.mapMenu.route($0) }
        table.register(SkillsMenuCoordinator.identifier) { [unowned front] in
            front.skillsMenu.route($0)
        }
    }
}
