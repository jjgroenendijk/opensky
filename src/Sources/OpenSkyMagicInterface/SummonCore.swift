import Foundation
public import OpenSkyFormatsESM

/// One actor a caster commands through a running effect.
nonisolated public struct CommandedActor: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case summoned
        case reanimated
    }

    public let actor: ReferenceKey
    public let caster: ReferenceKey
    public let kind: Kind
    /// The running effect that holds the actor: the actor it runs on and its sequence.
    public let holder: ReferenceKey
    public let sequence: UInt64

    public init(
        actor: ReferenceKey, caster: ReferenceKey, kind: Kind, holder: ReferenceKey,
        sequence: UInt64
    ) {
        self.actor = actor
        self.caster = caster
        self.kind = kind
        self.holder = holder
        self.sequence = sequence
    }
}
