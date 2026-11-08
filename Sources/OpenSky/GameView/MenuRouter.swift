// Routes menu keys and pointer events to the menu on top of the stack.

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

/// What `MenuRouter` reads from the session to wire the menus.
@MainActor
protocol MenuRouterHost: MenuSoundHost {
    var controlMapLoader: (() throws -> ControlMapFile)? { get }
    var mapWorld: any MapWorldPort { get }
    var menuTextLoader: (() -> any LocalizedLabelsPort)? { get }
    var messages: any MessageCoordinatorPort { get }
    var playerSettings: any PlayerSettingsPort { get }
}

final class MenuRouter {
    unowned let game: any MenuRouterHost
    private let hotkeys: MenuHotkeys
    let ticks: MenuFrameTick
    private let routeHosts: MenuRoutes
    let monitor = GamepadMonitor()
    var gamepads: any GamepadMonitorPort {
        monitor
    }

    init(game: some MenuRouterHost & MenuHotkeyHost & MenuTickHost & MenuRouteHosts) {
        self.game = game
        hotkeys = MenuHotkeys(game: game)
        ticks = MenuFrameTick(game: game)
        routeHosts = MenuRoutes(play: game, front: game)
    }

    /// The bound keys that open a menu or save, outside any menu, and the map's own keys.
    func run(_ action: GameInputAction) {
        hotkeys.run(action)
    }

    /// The one menu input consumer routes by the top of the menu stack. Each
    /// route checks that its own menu is open.
    func route(_ event: MenuInputEvent) {
        routes.route(event, top: routeHosts.front.menuMode.topMenu)
    }

    private lazy var routes = routeHosts.keyTable()

    /// The menus whose movie hit tests the cursor, so it must be visible.
    static let cursorMenus: [MenuIdentifier] = [
        TitleMenuCoordinator.identifier, RaceMenuCoordinator.identifier,
        MessageCoordinator.identifier
    ] + MenuScreens.cursorMenus

    /// A script opens the race menu during play, while look holds the cursor.
    func menuCursorFree(for route: InputRoute) -> Bool {
        route == .menu && routeHosts.front.menuMode.topMenu.map(Self.cursorMenus.contains) == true
    }

    /// A menu whose movie hit tests the cursor gets it. The other menus take a
    /// press as their accept button.
    func route(_ event: MenuPointerEvent) {
        if let route = routeHosts.front.menuMode.topMenu.flatMap({ pointerRoutes[$0] }) {
            route(event)
        } else if event.phase == .pressed {
            route(.button(.accept))
        }
    }

    /// The menus whose movie takes the cursor itself.
    private var pointerRoutes: [MenuIdentifier: (MenuPointerEvent) -> Void] {
        routeHosts.pointerTable()
    }
}
