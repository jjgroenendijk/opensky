// The menu coordinators the session scope builds, kept here so the scope's class body
// stays short.

import OpenSkyCells
import OpenSkyGameData
import OpenSkyMenus

extension GameSessionScope {
    func makeSystemMenu() -> SystemMenuCoordinator {
        let menu = SystemMenuCoordinator(
            menuMode: menuMode,
            movies: swfMovies,
            hud: hud,
            settings: playerSettings,
            saves: saveGames,
            world: self
        )
        menu.topicSource = messageWorld
        return menu
    }

    func makeRaceMenu() -> RaceMenuCoordinator {
        RaceMenuCoordinator(
            menuMode: menuMode,
            movies: swfMovies,
            hud: hud,
            world: menuWorld,
            morphCounts: worldData
                .map { FaceMorphCounts.resolve(store: $0.gameSettings) } ?? .vanilla
        )
    }

    func makeMenuScreenCoordinators() -> MenuScreenCoordinators {
        MenuScreenCoordinators(
            sleepWait: SleepWaitMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            training: TrainingMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            book: BookMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            tutorial: TutorialMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            magic: MagicMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            gift: GiftMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            crafting: CraftingMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            textEntry: TextEntryMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            ),
            creationClub: CreationClubMenuCoordinator(
                menuMode: menuMode, movies: swfMovies, hud: hud, world: menuScreensWorld
            )
        )
    }
}
