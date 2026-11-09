/// Where a new game puts the player.
nonisolated public enum NewGameStart: Equatable, Sendable {
    /// The vanilla opening: the opening quest moves the player and opens the race menu.
    case vanilla
    /// A cell by editor ID, for testing. The race menu opens at once.
    case cell(String)

    /// The game starts this quest on a new game by name: it is not start-game
    /// enabled and no `.seq` file lists it (docs/engine/main-menu.md).
    public static let openingQuest = "MQ101"
}
