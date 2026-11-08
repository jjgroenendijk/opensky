/// Which heartbeat the player's health asks for.
nonisolated public enum Heartbeat: Equatable, Sendable {
    case slow
    case fast
}

/// What the frame must do with the heartbeat sound.
nonisolated public enum HeartbeatChange: Equatable, Sendable {
    /// Stop the one playing at once, then start this one at full volume.
    case start(Heartbeat)
    /// Fade the one playing out over `PlayerHealthCues.heartbeatFadeSeconds`.
    case fadeOut
}
