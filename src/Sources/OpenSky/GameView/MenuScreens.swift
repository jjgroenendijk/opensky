// The smaller menu screens, built once per session: their coordinators, their key and
// cursor routes, and their frame tick. `MenuRouter` hands them the menu input.

import Foundation
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionInterface

/// What `MenuScreens` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuScreensHost: AnyObject {
    var journalMenu: any JournalMenuPort { get }
}

/// One screen's routes, so the tables below list each screen once. The routes hold their
/// screen strongly: for the tutorial and Creation Club screens they are its only owner.
struct MenuScreenRoute {
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
    let mapMovie: MapMenuMovieScreen
}

final class MenuScreens {
    let sleepWait: any SleepWaitMenuPort
    let training: any TrainingMenuPort
    let book: any BookMenuPort
    let magic: any MagicMenuPort
    let gift: any GiftMenuPort
    let crafting: any CraftingMenuPort
    let textEntry: TextEntryMenuCoordinator
    let mapMovie: MapMenuMovieScreen
    private let routes: [MenuScreenRoute]

    init(game: any MenuScreensHost, screens: MenuScreenCoordinators) {
        sleepWait = screens.sleepWait
        training = screens.training
        book = screens.book
        magic = screens.magic
        gift = screens.gift
        crafting = screens.crafting
        textEntry = screens.textEntry
        mapMovie = screens.mapMovie
        routes = [
            Self.route(screens.sleepWait), Self.route(screens.training), Self.route(screens.book),
            Self.route(screens.tutorial), Self.route(screens.magic), Self.route(screens.gift),
            Self.route(screens.crafting), Self.route(screens.textEntry),
            Self.route(screens.creationClub)
        ]
        mapMovie.onJournal = { [unowned game] in game.journalMenu.open() }
    }

    static func route(_ screen: MenuScreen<some Any>) -> MenuScreenRoute {
        MenuScreenRoute(
            identifier: screen.identifier,
            key: { screen.route($0) },
            pointer: { screen.route($0) },
            tick: { screen.tick(now: $0) }
        )
    }

    func tick(now: Double) {
        for route in routes {
            route.tick(now)
        }
        mapMovie.tick(now: now)
    }

    /// Each screen takes the keys while it is on top.
    var keyRoutes: [MenuIdentifier: (MenuInputEvent) -> Void] {
        Dictionary(uniqueKeysWithValues: routes.map { ($0.identifier, $0.key) })
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
