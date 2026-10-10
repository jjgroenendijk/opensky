// M16 acceptance: one guard through one day. A schedule picks a package, the
// guard walks a navmesh corridor through a door, notices the player, fights,
// breaks off wounded, searches, gives up, and resumes its package. Each step
// asserts runtime state, not only that a call returned. The panel, budget,
// render, and real-data halves live in the other `NPCAIAcceptance*` suites.

import Foundation
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyPerceptionInterface
@testable import OpenSkyPhysics
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import simd
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct NPCAIAcceptanceTests {
    /// The gate itself. One session lives the whole day and every step is
    /// checked before the next one runs, so a failure names the step rather
    /// than leaving an end state to reverse-engineer.
    @Test("one guard keeps a schedule, walks, detects, fights and resumes")
    func theRouteRunsTheWholeM16Loop() throws {
        let chain = try Chain()

        try Self.theScheduleSelectsTheMorningPackage(chain)
        try Self.theGuardWalksThroughTheDoor(chain)
        try Self.theGuardDetectsThePlayer(chain)
        try Self.theGuardFights(chain)
        try Self.theGuardLosesThePlayerAndSearches(chain)
        try Self.theGuardGivesUpAndResumesItsPackage(chain)
        try Self.theWoundedGuardBreaksOff(chain)
        try Self.expectEveryPhaseWasEntered(chain)
    }

    // MARK: - The route

    /// Step 1 — the clock decides. At nine in the morning the patrol's schedule
    /// matches and the sleep package's does not, and the selection carries the
    /// schedule that won so the readout can show why.
    private static func theScheduleSelectsTheMorningPackage(_ chain: Chain) throws {
        chain.setHour(9)
        chain.frame()

        let readout = try #require(chain.guardPackage)
        #expect(readout.currentPackage == NPCAIAcceptanceFixture.patrolPackage)
        #expect(readout.editorID == "NPCAIGuardPatrol")
        #expect(readout.procedure == .travel)
        #expect(readout.schedule?.hour == NPCAIAcceptanceFixture.patrolStartHour)
        #expect(chain.packageSelections.count == 1, "one selection, not one per frame")
    }

    /// Step 2 — the destination becomes a corridor and the corridor is walked.
    /// The door crossing is the piece that matters: an exterior sheet and an
    /// interior one are two graphs, and the guard arrives in the second having
    /// been handed off rather than having slid across the gap.
    private static func theGuardWalksThroughTheDoor(_ chain: Chain) throws {
        #expect(chain.moveGuard(to: Chain.bedPosition) == .started)
        let movingReadout = try #require(chain.guardMovement)
        #expect(movingReadout.state == .moving)
        #expect(movingReadout.waypointCount > 1)

        #expect(
            chain.run(frames: 4000) { chain.guardMovement?.state == .arrived },
            "the guard never reached the bed"
        )

        #expect(chain.doorCrossings == [Chain.marketDoor])
        let arrived = try #require(chain.guardMovement)
        #expect(arrived.state == .arrived)
        #expect(
            simd_distance(arrived.feetPosition, Chain.bedPosition)
                <= NPCMovementRuntime.waypointTolerance
        )
        #expect(arrived.repathCount == 0, "a clear corridor should need no repath")
        // The hand-off writes a settle point in the cell the guard ended up in,
        // which is what a save would carry.
        #expect(chain.settlePoints.map(\.reason).contains(.cellHandoff))
        #expect(chain.settlePoints.last?.reason == .arrival)
        #expect(chain.settlePoints.last?.cell == Chain.innCell)
    }

    /// Step 3 — perception. The player walks up to the guard inside the inn and
    /// the detection level climbs from nothing to detected, through the pass's
    /// own formula on its own fixed step.
    private static func theGuardDetectsThePlayer(_ chain: Chain) throws {
        #expect(chain.guardDetection.state == .unaware, "nothing should be perceived yet")
        chain.playerFeet = chain.guardFeet + SIMD3(80, 0, 0)
        chain.playerGait = .run

        #expect(
            chain.run(frames: 600) { chain.guardDetection.state == .detected },
            "the guard never noticed a player running at it"
        )
        let pair = chain.guardDetection
        #expect(pair.level > 0)
        #expect(pair.lastKnownPosition != nil)
    }

    /// Step 4 — the fight. Hostility plus a perceived player is the whole of
    /// combat entry: no spawn, no designation, no clock. The machine closes,
    /// reaches the player and starts swinging.
    private static func theGuardFights(_ chain: Chain) throws {
        chain.setGuardHostile(true)

        #expect(
            chain.run(frames: 900) { chain.combat.phase(of: Chain.guardKey)?.isAttacking == true },
            "the guard never attacked a player it had detected"
        )
        // And the swing is carried through to its contact step before the route
        // takes the player away, so a hit lands rather than being interrupted by
        // the next step of the gate.
        #expect(
            chain.run(frames: 900) {
                (chain.combat.behaviors[Chain.guardKey]?.contactCount ?? 0) > 0
            },
            "no swing ever reached its contact step"
        )
        let machine = try #require(chain.combat.behaviors[Chain.guardKey])
        #expect(machine.attackCount > 0)
        #expect(chain.combat.state.isPlayerInCombat)
        #expect(chain.visitedPhases.contains(.approaching), "it never closed the distance")
    }

    /// Step 5 — losing the player. Line of sight breaks, the detection level
    /// decays, and the place the player was last perceived becomes somewhere the
    /// guard walks to and looks around at.
    private static func theGuardLosesThePlayerAndSearches(_ chain: Chain) throws {
        chain.sightBlocked = { _, _ in true }
        #expect(
            chain.run(frames: 1800) { chain.combat.phase(of: Chain.guardKey) == .searching },
            "the guard never went looking for a player it had lost"
        )
        let machine = try #require(chain.combat.behaviors[Chain.guardKey])
        #expect(machine.searchCount > 0)
        // Searching still counts as being in the fight, which is what keeps the
        // combat music playing while an actor hunts.
        #expect(chain.combat.state.isPlayerInCombat)
    }

    /// Step 6 — the hand-back. Pursuit ends, the package runtime is asked for a
    /// fresh selection, and because the route scrubbed the clock into the
    /// evening on the way it gets the sleep package rather than the patrol it
    /// left off. That is the whole point of re-selecting rather than resuming a
    /// saved procedure.
    private static func theGuardGivesUpAndResumesItsPackage(_ chain: Chain) throws {
        chain.setHour(21)

        #expect(
            chain.run(frames: 3600) { chain.combat.phase(of: Chain.guardKey) == .disengaged },
            "the guard searched forever instead of giving up"
        )
        #expect(chain.packageResumes == [Chain.guardKey])
        #expect(!chain.combat.state.isPlayerInCombat, "a disengaged actor is out of combat")

        let readout = try #require(chain.guardPackage)
        #expect(readout.currentPackage == NPCAIAcceptanceFixture.sleepPackage)
        #expect(readout.editorID == "NPCAIGuardSleep")
        #expect(readout.procedure == .sleep)
    }

    /// Step 7: giving up does not end the quarrel, so the guard re-engages on
    /// sight. Wounding it mid-fight then makes it flee. An actor already under
    /// the flee threshold never starts a fight, so it is engaged first.
    private static func theWoundedGuardBreaksOff(_ chain: Chain) throws {
        chain.sightBlocked = { _, _ in false }
        chain.playerFeet = chain.guardFeet + SIMD3(80, 0, 0)
        #expect(
            chain.run(frames: 1800) {
                chain.combat.phase(of: Chain.guardKey)?.isEngaged == true
            },
            "the guard never re-engaged a player it still had a quarrel with"
        )

        chain.woundGuard(to: 0.1)
        #expect(
            chain.run(frames: 1800) { chain.combat.phase(of: Chain.guardKey) == .fleeing },
            "a guard at ten percent health never broke off"
        )
        #expect(chain.combat.state.isPlayerInCombat, "a fleeing actor is still in the fight")

        // Past the break distance the pursuit ends like a finished search. The
        // player moves instead of the guard, because the arena's navmesh is
        // 200 units long and the flee distance is 1,400. The break is a distance
        // test, so either side may open the gap.
        chain.playerFeet = chain.guardFeet
            + SIMD3(CombatBehaviorSettings.standard.fleeBreakDistance + 100, 0, 0)
        #expect(
            chain.run(frames: 600) { chain.combat.phase(of: Chain.guardKey) == .disengaged },
            "the guard stayed in a fight with a player two thousand units away"
        )
        #expect(chain.packageResumes.count == 2, "the second exit handed it back too")
    }

    /// Every phase the milestone claims was entered by the machine on its own
    /// clock. `contact` is checked through the machine's own count: it lasts one
    /// fixed step, and a frame that runs two steps can skip it in a sample.
    private static func expectEveryPhaseWasEntered(_ chain: Chain) throws {
        for phase in [
            CombatBehaviorPhase.approaching, .spacing, .windup,
            .fleeing, .searching, .disengaged
        ] {
            #expect(chain.visitedPhases.contains(phase), "never entered \(phase.rawValue)")
        }
        let machine = try #require(chain.combat.behaviors[Chain.guardKey])
        #expect(machine.contactCount > 0, "no swing ever reached its contact step")
        #expect(machine.fightCount == 2, "the guard fought twice, from one quarrel")
    }

    private typealias Chain = NPCAIAcceptanceChain
}
