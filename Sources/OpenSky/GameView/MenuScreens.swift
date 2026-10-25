// The smaller menu screens, built once per session: their coordinators, their key and
// cursor routes, and their frame tick. `MenuRouter` hands them the menu input.

import Foundation
import OpenSkyMenus

/// What `MenuScreens` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuScreensHost: AnyObject {
    var hud: HUDCoordinator { get }
    var journalMenu: JournalMenuController { get }
    var mapMenu: MapMenuCoordinator { get }
    var menuScreensWorld: MenuScreensWorldAdapter { get }
    var swfMovies: SWFMovieSource { get }
}

/// One screen's routes, so the tables below list each screen once.
private struct MenuScreenRoute {
    let identifier: MenuIdentifier
    let key: (MenuInputEvent) -> Void
    let pointer: (MenuPointerEvent) -> Void
    let tick: (Double) -> Void
}

/// The screens' coordinators, built by the session scope.
struct MenuScreenCoordinators {
    let sleepWait: SleepWaitMenuCoordinator
    let training: TrainingMenuCoordinator
    let book: BookMenuCoordinator
    let tutorial: TutorialMenuCoordinator
    let magic: MagicMenuCoordinator
    let gift: GiftMenuCoordinator
    let crafting: CraftingMenuCoordinator
    let textEntry: TextEntryMenuCoordinator
    let creationClub: CreationClubMenuCoordinator
}

final class MenuScreens {
    let sleepWait: SleepWaitMenuCoordinator
    let training: TrainingMenuCoordinator
    let book: BookMenuCoordinator
    let tutorial: TutorialMenuCoordinator
    let magic: MagicMenuCoordinator
    let gift: GiftMenuCoordinator
    let crafting: CraftingMenuCoordinator
    let textEntry: TextEntryMenuCoordinator
    let creationClub: CreationClubMenuCoordinator
    let mapMovie: MapMenuMovieScreen

    init(game: any MenuScreensHost, screens: MenuScreenCoordinators) {
        let world = game.menuScreensWorld
        let (movies, hud) = (game.swfMovies, game.hud)
        sleepWait = screens.sleepWait
        training = screens.training
        book = screens.book
        tutorial = screens.tutorial
        magic = screens.magic
        gift = screens.gift
        crafting = screens.crafting
        textEntry = screens.textEntry
        creationClub = screens.creationClub
        mapMovie = MapMenuMovieScreen(map: game.mapMenu, movies: movies, hud: hud, world: world)
        mapMovie.onJournal = { [unowned game] in game.journalMenu.open() }
    }

    private var routes: [MenuScreenRoute] {
        [
            Self.route(sleepWait), Self.route(training), Self.route(book),
            Self.route(tutorial), Self.route(magic), Self.route(gift), Self.route(crafting),
            Self.route(textEntry), Self.route(creationClub)
        ]
    }

    private static func route(_ screen: MenuScreen<some Any>) -> MenuScreenRoute {
        MenuScreenRoute(
            identifier: screen.identifier,
            key: { [unowned screen] in screen.route($0) },
            pointer: { [unowned screen] in screen.route($0) },
            tick: { [unowned screen] in screen.tick(now: $0) }
        )
    }

    func tick(now: Double) {
        for route in routes {
            route.tick(now)
        }
        mapMovie.tick(now: now)
    }

    /// Each screen takes the keys while it is on top.
    func register(in table: MenuRouteTable) {
        for route in routes {
            table.register(route.identifier, route: route.key)
        }
    }

    /// The screens whose movie takes the cursor.
    var pointerRoutes: [MenuIdentifier: (MenuPointerEvent) -> Void] {
        Dictionary(uniqueKeysWithValues: routes.map { ($0.identifier, $0.pointer) })
    }

    static let cursorMenus: [MenuIdentifier] = [
        SleepWaitMenuCoordinator.identifier, TrainingMenuCoordinator.identifier,
        BookMenuCoordinator.identifier, TutorialMenuCoordinator.identifier,
        MagicMenuCoordinator.identifier, GiftMenuCoordinator.identifier,
        CraftingMenuCoordinator.identifier, TextEntryMenuCoordinator.identifier,
        CreationClubMenuCoordinator.identifier
    ]
}
