// Bounds on everything a fight spawns (issue #374, roadmap item 15.7, scope
// point 5).
//
// Four populations grow while a fight runs and none of them shrinks on its own:
// arrows in flight, arrows standing in what they hit, corpses simulating, and
// clutter the fight knocked awake. Left alone, a long session in one room ends
// with a thousand of each, and the frame budget the milestone gate measures
// stops meaning anything.
//
// The numbers are OpenSky's, not Bethesda's. Vanilla's own caps live in its
// code rather than in any record this engine reads, and there is no open source
// that states them, so inventing a number and citing it would be worse than
// choosing one and saying it was chosen. Each is picked from what the engine
// can actually carry at frame rate — the 15.2 clutter stress and the 15.6
// repeated-collapse stress are the measurements behind them — and is stated on
// its own field.
//
// Trimming order is per population, and the difference is worth stating because
// only two of the three registries know what "oldest" means. Projectiles and
// ragdolls do — both are appended to in spawn order — so those trim oldest
// first. Dynamic bodies do not: a body is placed by its cell build and carries
// no spawn time, so the awake cap sleeps them in ascending `ReferenceKey`, the
// registry's own order everywhere else.
//
// Nothing here deletes what a player is looking at. A capped corpse stops
// simulating and falls back to the resting transform its death state recorded;
// a capped body sleeps where it stands. The cap costs motion, not position.
//
// Documented in docs/engine/combat.md.

import Foundation

/// The ceiling on each transient population.
nonisolated struct CombatTransientLimits: Equatable, Sendable {
    /// Arrows in the air at once. Twelve is well past what a bow can loose in
    /// the time the first arrow is still flying, so the cap is a runaway guard
    /// rather than a gameplay rule.
    var liveProjectiles: Int
    /// Arrows left standing in the world. Chosen so a full quiver emptied into
    /// one wall stays visible; past it the oldest is pulled out.
    var stuckProjectiles: Int
    /// Corpses simulating at once. The 15.6 stress runs eight collapsing
    /// together inside budget, so eight is the measured number rather than a
    /// hoped-for one.
    var activeRagdolls: Int
    /// Dynamic bodies awake at once. The 15.2 stress settles this many inside
    /// the step budget; past it the oldest awake body is put to sleep where it
    /// is rather than deleted.
    var awakeBodies: Int

    /// What a session runs with.
    static let standard = CombatTransientLimits(
        liveProjectiles: 12,
        stuckProjectiles: 32,
        activeRagdolls: 8,
        awakeBodies: 64
    )

    init(
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
    func excess(over counts: CombatTransientCounts) -> CombatTransientCounts {
        CombatTransientCounts(
            liveProjectiles: max(0, counts.liveProjectiles - liveProjectiles),
            stuckProjectiles: max(0, counts.stuckProjectiles - stuckProjectiles),
            activeRagdolls: max(0, counts.activeRagdolls - activeRagdolls),
            awakeBodies: max(0, counts.awakeBodies - awakeBodies)
        )
    }

    /// Whether any population is over its ceiling.
    func needsTrim(_ counts: CombatTransientCounts) -> Bool {
        excess(over: counts) != .none
    }
}
