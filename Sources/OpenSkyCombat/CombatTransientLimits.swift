// Caps on what a fight spawns: flying arrows, stuck arrows, simulating corpses, awake
// clutter. Our numbers, sized from the clutter and ragdoll stress tests. Arrows and
// ragdolls trim oldest first; bodies have no spawn time, so they sleep by `ReferenceKey`.
// A cap stops motion, never moves anything. See docs/engine/combat.md.

import Foundation

/// The ceiling on each transient population.
nonisolated public struct CombatTransientLimits: Equatable, Sendable {
    /// Arrows in the air at once. Twelve is well past what a bow can loose in
    /// the time the first arrow is still flying, so the cap is a runaway guard
    /// rather than a gameplay rule.
    public var liveProjectiles: Int
    /// Arrows left standing in the world. Chosen so a full quiver emptied into
    /// one wall stays visible; past it the oldest is pulled out.
    public var stuckProjectiles: Int
    /// Corpses simulating at once. The 15.6 stress runs eight collapsing
    /// together inside budget, so eight is the measured number rather than a
    /// hoped-for one.
    public var activeRagdolls: Int
    /// Dynamic bodies awake at once. The 15.2 stress settles this many inside
    /// the step budget; past it the oldest awake body is put to sleep where it
    /// is rather than deleted.
    public var awakeBodies: Int

    /// What a session runs with.
    public static let standard = CombatTransientLimits(
        liveProjectiles: 12,
        stuckProjectiles: 32,
        activeRagdolls: 8,
        awakeBodies: 64
    )

    public init(
        liveProjectiles: Int,
        stuckProjectiles: Int,
        activeRagdolls: Int,
        awakeBodies: Int
    ) {
        self.liveProjectiles = max(0, liveProjectiles)
        self.stuckProjectiles = max(0, stuckProjectiles)
        self.activeRagdolls = max(0, activeRagdolls)
        self.awakeBodies = max(0, awakeBodies)
    }

    /// How many of each population is over its ceiling, given live counts.
    /// Zero in every field when nothing needs trimming, which is the common
    /// case and costs four comparisons.
    public func excess(over counts: CombatTransientCounts) -> CombatTransientCounts {
        CombatTransientCounts(
            liveProjectiles: max(0, counts.liveProjectiles - liveProjectiles),
            stuckProjectiles: max(0, counts.stuckProjectiles - stuckProjectiles),
            activeRagdolls: max(0, counts.activeRagdolls - activeRagdolls),
            awakeBodies: max(0, counts.awakeBodies - awakeBodies)
        )
    }

    /// Whether any population is over its ceiling.
    public func needsTrim(_ counts: CombatTransientCounts) -> Bool {
        excess(over: counts) != .none
    }
}
