import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyPhysics
import simd

/// What a melee hit does to its target.
nonisolated public struct HitKnock: Equatable, Sendable {
    /// Units per second along the ground, away from the attacker.
    public let speed: Float
    /// The hit passed the knockdown test, so the target falls.
    public let isKnockdown: Bool

    public init(
        speed: Float,
        isKnockdown: Bool
    ) {
        self.speed = speed
        self.isKnockdown = isKnockdown
    }
}

/// How an explosion knocks down the actors in it, from its `EXPL` flags.
nonisolated public enum ExplosionKnockdown: Equatable, Sendable {
    case never, always, byFormula

    /// Flag 0x4 knocks down always, 0x8 by the knockdown formula.
    public init(flags: UInt32?) {
        let flags = flags ?? 0
        self = flags & 0x4 != 0 ? .always : flags & 0x8 != 0 ? .byFormula : .never
    }
}
