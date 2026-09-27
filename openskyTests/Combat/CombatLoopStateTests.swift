// Derived combat state and the transient caps (issue #374, roadmap item 15.7).
//
// Both subjects are pure values, so both suites are arithmetic over literals.
// What is pinned here is the derivation rule the whole loop rests on — in
// combat means "some resident actor is hostile and alive", and the target is
// the nearest of those — because every consumer downstream, the music edge and
// 15.8's combat-target condition among them, reads exactly that answer.

@testable import opensky
import simd
import Testing

struct CombatLoopStateTests {
    private static func actor(
        _ id: UInt64,
        at x: Float,
        dead: Bool = false
    ) -> CombatActorObservation {
        CombatActorObservation(
            key: .generated(id),
            feet: SIMD3(x, 0, 0),
            isDead: dead,
            name: "actor \(id)"
        )
    }

    /// Derives with every hostile actor also *engaged*, which is what a fight
    /// with a perception pass under it looks like. The engagement half is
    /// varied on its own in `hostilityWithoutEngagementIsNotCombat`.
    private static func derive(
        _ actors: [CombatActorObservation],
        hostile: Set<ReferenceKey>,
        engaged: Set<ReferenceKey>? = nil
    ) -> CombatLoopState {
        let fighting = engaged ?? hostile
        return CombatLoopState.derive(
            actors: actors,
            hostility: { hostile.contains($0) ? .hostile : .neutral },
            phase: { fighting.contains($0) ? .approaching : .idle },
            playerFeet: SIMD3<Float>()
        )
    }

    /// Item 16.7 moved the combat edge from "somebody is angry" to "somebody is
    /// fighting". A hostile actor that has not perceived the player yet is not
    /// a fight, which is what makes the music stop when the fight ends rather
    /// than when the actor is finally killed or calmed.
    @Test func hostilityWithoutEngagementIsNotCombat() {
        let state = Self.derive(
            [Self.actor(1, at: 300)], hostile: [.generated(1)], engaged: []
        )
        #expect(state.hostileCount == 1)
        #expect(state.engagedCount == 0)
        #expect(!state.isPlayerInCombat)
        // The player's target is still the nearest hostile, engaged or not.
        #expect(state.target == .generated(1))
    }

    @Test func aSearchingActorIsCountedAndIsStillCombat() {
        let state = CombatLoopState.derive(
            actors: [Self.actor(1, at: 300)],
            hostility: { _ in .hostile },
            phase: { _ in .searching },
            playerFeet: SIMD3<Float>()
        )
        #expect(state.isPlayerInCombat)
        #expect(state.engagedCount == 1)
        #expect(state.searchingCount == 1)
    }

    @Test func aWorldOfNeutralActorsIsNotCombat() {
        let state = Self.derive([Self.actor(1, at: 100), Self.actor(2, at: 200)], hostile: [])
        #expect(state == .calm)
    }

    @Test func oneHostileLivingActorIsCombatAndIsTheTarget() {
        let state = Self.derive(
            [Self.actor(1, at: 300), Self.actor(2, at: 200)],
            hostile: [.generated(2)]
        )
        #expect(state.isPlayerInCombat)
        #expect(state.target == .generated(2))
        #expect(state.targetName == "actor 2")
        #expect(state.targetDistance == 200)
        #expect(state.hostileCount == 1)
    }

    @Test func theNearestHostileWins() {
        let state = Self.derive(
            [Self.actor(1, at: 500), Self.actor(2, at: 120), Self.actor(3, at: 300)],
            hostile: [.generated(1), .generated(2), .generated(3)]
        )
        #expect(state.target == .generated(2))
        #expect(state.hostileCount == 3)
    }

    @Test func twoHostilesOnTheSameSpotBreakOnTheLowerReference() {
        let state = Self.derive(
            [Self.actor(9, at: 150), Self.actor(4, at: 150)],
            hostile: [.generated(9), .generated(4)]
        )
        #expect(state.target == .generated(4))
    }

    @Test func aDeadHostileIsNeitherCountedNorTargeted() {
        let state = Self.derive(
            [Self.actor(1, at: 100, dead: true)],
            hostile: [.generated(1)]
        )
        #expect(!state.isPlayerInCombat)
        #expect(state.target == nil)
        #expect(state.hostileCount == 0)
        #expect(state.deadCount == 1)
    }

    @Test func killingTheLastHostileLeavesCombat() {
        let living = [Self.actor(1, at: 100)]
        let dead = [Self.actor(1, at: 100, dead: true)]
        #expect(Self.derive(living, hostile: [.generated(1)]).isPlayerInCombat)
        #expect(!Self.derive(dead, hostile: [.generated(1)]).isPlayerInCombat)
    }
}

struct CombatTransientLimitsTests {
    @Test func nothingOverTheCeilingNeedsNoTrim() {
        let limits = CombatTransientLimits.standard
        let counts = CombatTransientCounts(
            liveProjectiles: limits.liveProjectiles,
            stuckProjectiles: limits.stuckProjectiles,
            activeRagdolls: limits.activeRagdolls,
            awakeBodies: limits.awakeBodies
        )
        #expect(!limits.needsTrim(counts))
        #expect(limits.excess(over: counts) == .none)
    }

    @Test func eachPopulationIsMeasuredAgainstItsOwnCeiling() {
        let limits = CombatTransientLimits(
            liveProjectiles: 2, stuckProjectiles: 3, activeRagdolls: 1, awakeBodies: 4
        )
        let counts = CombatTransientCounts(
            liveProjectiles: 5, stuckProjectiles: 3, activeRagdolls: 4, awakeBodies: 0
        )
        #expect(limits.needsTrim(counts))
        #expect(limits.excess(over: counts) == CombatTransientCounts(
            liveProjectiles: 3, stuckProjectiles: 0, activeRagdolls: 3, awakeBodies: 0
        ))
    }

    @Test func aNegativeCeilingIsClampedToZeroRatherThanInverted() {
        let limits = CombatTransientLimits(
            liveProjectiles: -4, stuckProjectiles: 0, activeRagdolls: 0, awakeBodies: 0
        )
        #expect(limits.liveProjectiles == 0)
        #expect(limits.excess(
            over: CombatTransientCounts(liveProjectiles: 1)
        ).liveProjectiles == 1)
    }
}
