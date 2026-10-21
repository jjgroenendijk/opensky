// Summoned and reanimated actors as pure rules: how many one caster commands, and which
// one goes when a new one passes the limit. CK wiki "Magic Effect": Summon Creature
// "Summons the specified creature, placing them under the caster's control"; Reanimate
// "If the target is dead, reanimate them". See docs/engine/magic-archetypes.md.

import Foundation
import OpenSkyFormatsESM

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

nonisolated public enum SummonCore {
    /// UESP "Skyrim:Conjuration": Twin Souls lets the player have "two atronachs or
    /// reanimated zombies", and adds 1 at entry point 68, so the base is 1.
    public static let baseCommandLimit: Float = 1

    /// `commanded` with `actor` added. Past `limit`, the caster's oldest actors go.
    public static func commanding(
        _ actor: CommandedActor, in commanded: [CommandedActor], limit: Int
    ) -> (kept: [CommandedActor], released: [CommandedActor]) {
        var kept = commanded + [actor]
        var released: [CommandedActor] = []
        while kept.count(where: { $0.caster == actor.caster }) > max(1, limit) {
            guard let oldest = kept.firstIndex(where: { $0.caster == actor.caster }) else { break }
            released.append(kept.remove(at: oldest))
        }
        return (kept: kept, released: released)
    }

    /// The actor that the end of effect `sequence` on `holder` releases.
    public static func ending(
        _ sequence: UInt64, on holder: ReferenceKey, in commanded: [CommandedActor]
    ) -> Int? {
        commanded.firstIndex { $0.holder == holder && $0.sequence == sequence }
    }
}
