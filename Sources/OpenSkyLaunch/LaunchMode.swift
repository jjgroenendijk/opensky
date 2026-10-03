// The ways the app can start. The app gives each mode a button; a new mode is
// one case here and one descriptor in the app's launcher.

nonisolated public enum LaunchMode: String, CaseIterable, Sendable {
    /// The game alone: no sidebar, no inspector, no frame HUD.
    case play
    /// The developer shell: sidebar destinations and inspector panels.
    case developer

    /// The developer shell shows a demo scene without an install; play does not.
    public var requiresGameData: Bool {
        switch self {
        case .play: true
        case .developer: false
        }
    }
}
