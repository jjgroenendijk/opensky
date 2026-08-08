// The M15 gate's determinism and pause claims (issue #198), in a satellite of
// `M15AcceptanceTests.swift` beside the route steps.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
extension M15AcceptanceTests {
    // MARK: - Determinism

    /// Two runs of the same fight produce the same trace, which is what makes
    /// every number above evidence rather than a sample.
    @Test("the fight is deterministic")
    func theFightRepeatsExactly() throws {
        let first = try Self.shortFight()
        let second = try Self.shortFight()
        #expect(first.states == second.states)
        #expect(first.opponentHealth == second.opponentHealth)
        #expect(first.playerHealth == second.playerHealth)
        #expect(first.hits == second.hits)
        #expect(first.crate == second.crate)
        #expect(first.snapshot == second.snapshot)
    }

    /// A shortened fight — draw, anger, swing, settle — run twice for the
    /// determinism claim. The full route is driven once by the gate above; what
    /// this needs is repetition, not length.
    static func shortFight() throws -> M15FightTrace {
        let chain = try Chain()
        chain.capturePointer()
        chain.press(.keyR)
        chain.run(frames: 60) { chain.melee.state.drawState == .drawn }
        _ = chain.combat.spawnDevTarget()
        chain.clickAttack()
        chain.run(frames: 90)
        chain.run(frames: 600) { chain.crateBody?.isSleeping == true }
        return M15FightTrace(
            states: chain.visitedStates,
            opponentHealth: chain.opponentHealth,
            playerHealth: chain.playerHealth,
            hits: chain.melee.trace,
            crate: chain.crateBody?.position,
            snapshot: chain.store.snapshot()
        )
    }

    // MARK: - Bounds

    /// A paused frame advances nothing: no graph update, no swing, no arrow, no
    /// body movement and no fight. That is the menu-mode rule, and it has to
    /// hold for combat as well as for locomotion.
    @Test("a paused frame advances no part of the fight")
    func aPausedFrameAdvancesNothing() throws {
        let chain = try Chain()
        chain.capturePointer()
        chain.press(.keyR)
        chain.run(frames: 60) { chain.melee.state.drawState == .drawn }
        _ = chain.combat.spawnDevTarget()
        chain.run(frames: 30)

        let updates = chain.graph.tally.updatesRun
        let position = chain.crateBody?.position
        let hits = chain.combat.incomingHitCount
        let health = chain.playerHealth

        for _ in 0 ..< 40 {
            chain.frame(dt: 0)
        }

        #expect(chain.graph.tally.updatesRun == updates, "a paused frame stepped the graph")
        #expect(chain.crateBody?.position == position, "a paused frame moved a body")
        #expect(chain.combat.incomingHitCount == hits, "a paused frame landed a blow")
        #expect(chain.playerHealth == health)
    }
}

/// What one run of the fight left behind, compared whole between two runs.
struct M15FightTrace {
    let states: [String]
    let opponentHealth: Float
    let playerHealth: Float
    let hits: [MeleeHitRecord]
    let crate: SIMD3<Float>?
    let snapshot: WorldStateSnapshot
}
