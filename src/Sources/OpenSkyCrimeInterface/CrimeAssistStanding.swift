// How the crime state judges an actor in a fight, for a helper with a Morality.
// See docs/engine/combat.md#committed-a-crime.

/// Whether a helper counts an actor a criminal.
nonisolated public enum CrimeAssistStanding: Equatable, Sendable {
    case clean
    case criminal
    /// The player resisted the helper's crime faction a while ago. The player counts as a
    /// criminal only while a guard fights them.
    case criminalWhileAGuardFights
}
