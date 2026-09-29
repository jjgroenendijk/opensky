// Limits the world's actor movement sets, which combat reads too.

/// How many actors the world moves at once.
nonisolated public enum ActorMovementLimits {
    /// Named crowd cap. Only actors with an active request own a controller.
    public static let maximumSimultaneousMovers = 8
}
