// The ways the app can start. The app gives each mode a button; a new mode is
// one case here and one descriptor in the app's launcher.

nonisolated public enum LaunchMode: String, CaseIterable, Sendable {
    /// The game alone: no sidebar, no inspector, no frame HUD.
    case play
    /// The developer shell: sidebar destinations and inspector panels.
    case developer

    /// Play opens on the game's main menu, as the original game does. The
    /// developer shell opens in the world, so a check starts where it acts.
    public var opensAtTitleScreen: Bool {
        self == .play
    }

    /// The developer shell shows a demo scene without an install; play does not.
    public var requiresGameData: Bool {
        switch self {
        case .play: true
        case .developer: false
        }
    }
}
