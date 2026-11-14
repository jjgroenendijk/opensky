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

/// The opening, done without playing it. The opening quest has a quick start entry in
/// its start-up stage; these are the stages that entry sets, without its move of the
/// player and its race menu (docs/engine/main-menu.md).
nonisolated public enum OpeningSkip {
    /// Who the player left Helgen with. The quick start entry asks this in a message box.
    public enum Side: Equatable, Sendable {
        case hadvar
        case ralof

        /// The quest that brings this companion to Riverwood.
        public var quest: String {
            switch self {
            case .hadvar: "MQ102A"
            case .ralof: "MQ102B"
            }
        }
    }

    public static let companionStage: UInt16 = 1
    /// The last one stops the opening quest.
    public static let openingStages: [UInt16] = [25, 26, 1000]
}
