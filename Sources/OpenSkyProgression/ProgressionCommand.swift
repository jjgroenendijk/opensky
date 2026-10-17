// What the progression domain asks the app to do. The coordinator collects these
// and the app runs them each frame (docs/engine/coordinators.md, Commands).

/// One change outside the progression domain.
nonisolated public enum ProgressionCommand: Equatable, Sendable {
    /// A HUD notice, such as a skill increase or a refused training session.
    case showNotification(String)
    /// Adds one to a misc stat, such as "Training Sessions".
    case incrementStat(String)
}
