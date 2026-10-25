// Main-app melee inspection seam: draw state, attack phase, the last-hit trace,
// and the melee keys as controls. One snapshot value, so the readout comes from
// a single engine observation. AppKit-free.

import Foundation

/// One landed hit as a readout spells it.
nonisolated public struct MeleeHitReadout: Equatable, Sendable {
    /// The target reference, as its `ReferenceKey` description.
    public let target: String
    /// What actually came off health.
    public let appliedDamage: Float

    public init(
        target: String,
        appliedDamage: Float
    ) {
        self.target = target
        self.appliedDamage = appliedDamage
    }
}

/// One observation of the melee runtime.
nonisolated public struct MeleeCombatSnapshot: Equatable, Sendable {
    public let hitCount: Int
    /// The last-hit trace, oldest first.
    public let trace: [MeleeHitReadout]

    /// The reading with no runtime attached.
    public static let unavailable = MeleeCombatSnapshot(
        hitCount: 0,
        trace: []
    )

    public init(
        hitCount: Int,
        trace: [MeleeHitReadout]
    ) {
        self.hitCount = hitCount
        self.trace = trace
    }
}
