// The vanilla movies a bridge in this module drives. `openskycli gaps` lists every
// other movie that talks to the engine as a menu with no bridge. A new bridge adds
// its movie here.

import Foundation

nonisolated public enum MenuMovieBridges: Sendable {
    /// Lowercased archive paths.
    public static let moviePaths: Set<String> = [
        BookMenuBarMovieBridge.moviePath,
        BookMenuMovieBridge.moviePath,
        ContainerMenuMovieBridge.barterMoviePath,
        ContainerMenuMovieBridge.containerMoviePath,
        CraftingMenuMovieBridge.moviePath,
        CreationClubMenuMovieBridge.moviePath,
        CreditsMenuMovieBridge.moviePath,
        DialogueMenuMovieBridge.moviePath,
        HUDMovieBridge.moviePath,
        InventoryMenuMovieBridge.moviePath,
        ItemListMenuMovieBridge.giftMoviePath,
        ItemListMenuMovieBridge.magicMoviePath,
        LevelUpMenuMovieBridge.moviePath,
        LockpickingMenuMovieBridge.moviePath,
        MapMenuMovieBridge.moviePath,
        MessageBoxMovieBridge.moviePath,
        QuestJournalMovieBridge.moviePath,
        RaceMenuMovieBridge.moviePath,
        SleepWaitMenuMovieBridge.moviePath,
        StatsMenuMovieBridge.moviePath,
        SystemMenuMovieBridge.moviePath,
        TextEntryMenuMovieBridge.moviePath,
        TitleMenuMovieBridge.moviePath,
        TrainingMenuMovieBridge.moviePath,
        TutorialMenuMovieBridge.moviePath
    ]
}
