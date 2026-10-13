// The vanilla movies a bridge in this module drives. `openskycli gaps` lists every
// other movie that talks to the engine as a menu with no bridge. A new bridge adds
// its movie here.

import Foundation

nonisolated public enum MenuMovieBridges: Sendable {
    /// Lowercased archive paths.
    public static let moviePaths: Set<String> = [
        ContainerMenuMovieBridge.barterMoviePath,
        ContainerMenuMovieBridge.containerMoviePath,
        DialogueMenuMovieBridge.moviePath,
        HUDMovieBridge.moviePath,
        InventoryMenuMovieBridge.moviePath,
        LevelUpMenuMovieBridge.moviePath,
        QuestJournalMovieBridge.moviePath,
        RaceMenuMovieBridge.moviePath,
        StatsMenuMovieBridge.moviePath,
        SystemMenuMovieBridge.moviePath,
        TitleMenuMovieBridge.moviePath
    ]
}
