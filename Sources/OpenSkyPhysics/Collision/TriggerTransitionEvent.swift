import OpenSkyFormatsESM

/// One trigger-occupancy edge. Identity is the authoring REFR's
/// `ReferenceKey`, because that is what a script instance is addressed by.
nonisolated public struct TriggerTransitionEvent: Equatable, Sendable {
    nonisolated public enum Phase: Equatable, Sendable {
        case enter
        case leave
    }

    public let reference: ReferenceKey
    public let phase: Phase
    /// The occupying actor. Nil preserves the player-capsule event surface;
    /// NPC movers name themselves so Papyrus receives the correct activator.
    public var actor: ReferenceKey?

    public init(reference: ReferenceKey, phase: Phase, actor: ReferenceKey? = nil) {
        self.reference = reference
        self.phase = phase
        self.actor = actor
    }
}
