// The smaller menu screens, built once per session: their coordinators, their key and
// cursor routes, and their frame tick. `MenuRouter` hands them the menu input.

import Foundation
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld

/// What `MenuScreens` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuScreensHost: AnyObject {
    var hud: HUDCoordinator { get }
    var journalMenu: JournalMenuController { get }
    var mapMenu: MapMenuCoordinator { get }
    var menuMode: MenuModeController { get }
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

    init(game: any MenuScreensHost) {
        let world = game.menuScreensWorld
        let (menuMode, movies, hud) = (game.menuMode, game.swfMovies, game.hud)
        sleepWait = SleepWaitMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        training = TrainingMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        book = BookMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        tutorial = TutorialMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        magic = MagicMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        gift = GiftMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        crafting = CraftingMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        textEntry = TextEntryMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
        creationClub = CreationClubMenuCoordinator(
            menuMode: menuMode, movies: movies, hud: hud, world: world
        )
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

    private static func route<Event>(_ screen: MenuScreen<Event>) -> MenuScreenRoute {
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

extension MenuScreens: MenuScreensControlProviding {
    var menuScreenReadouts: [MenuScreenReadout] {
        MenuScreenKind.allCases.map { kind in
            let (state, result) = readout(of: kind)
            return MenuScreenReadout(kind: kind, state: state, lastResult: result)
        }
    }

    private func readout(of kind: MenuScreenKind) -> (String, String) {
        switch kind {
        case .wait, .rest: (sleepWait.movieState, sleepWait.lastResult)
        case .training: (training.movieState, training.lastResult)
        case .book: (book.movieState, book.lastResult)
        case .help: (tutorial.movieState, tutorial.lastResult)
        case .magic: (magic.movieState, magic.lastResult)
        case .gift: (gift.movieState, gift.lastResult)
        case .crafting: (crafting.movieState, crafting.lastResult)
        case .map: (mapMovie.movieState, mapMovie.map.lastResult ?? "none")
        case .textEntry: (textEntry.movieState, textEntry.lastResult)
        case .creationClub: (creationClub.movieState, creationClub.lastResult)
        }
    }

    @discardableResult
    func openMenuScreen(_ kind: MenuScreenKind) -> Bool {
        switch kind {
        case .wait: sleepWait.open(sleeping: false)
        case .rest: sleepWait.open(sleeping: true)
        case .training: training.openNearest()
        case .book: book.openFirstCarried()
        case .help: tutorial.openFirstTopic()
        case .magic: magic.open()
        case .gift: gift.openNearest()
        case .crafting: crafting.open()
        case .map: mapMovie.map.open()
        case .textEntry: textEntry.open(title: "Name")
        case .creationClub: creationClub.open()
        }
    }
}
