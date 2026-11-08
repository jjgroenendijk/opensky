// The Behaviour Graphs section's seam: the switch, the distance cutoff, and the
// selected actor's running graph.

/// How often an actor's graph stepped on the last frame.
nonisolated public enum ActorGraphStepRate: String, Equatable, Sendable {
    case full
    case reduced
    case stopped
}
