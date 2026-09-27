// M16 acceptance (issue #203): one guard, one day, through every AI capability
// the milestone claims.
//
// The gate statement in one run: a schedule selects a package off the game
// clock, the package's destination becomes a navmesh corridor, the guard walks
// that corridor out of the market and through a door into the inn, the
// perception pass notices the player standing in front of it, the combat machine
// closes and fights, the guard breaks off wounded, hunts for a player who broke
// line of sight, gives up, and is handed back to the package its schedule now
// names.
//
// Every step asserts what a runtime holds, not just that a call returned: which
// package won and why, which door the corridor crossed, what the detection level
// reached, which phases the machine entered in which order, and which package
// the resume produced. The panel half is `M16AcceptancePanelTests`, the budget
// half is `M16AcceptanceBudgetTests`, the pixel half is
// `M16AcceptanceRenderTests` and the vanilla half is
// `M16AcceptanceRealDataTests`; the last two are gated, and everything here runs
// on a device-less runner with no install.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct M16AcceptanceTests {
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
        #expect(readout.currentPackage == M16AcceptanceFixture.patrolPackage)
        #expect(readout.editorID == "M16GuardPatrol")
        #expect(readout.procedure == .travel)
        #expect(readout.schedule?.hour == M16AcceptanceFixture.patrolStartHour)
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
        #expect(readout.currentPackage == M16AcceptanceFixture.sleepPackage)
        #expect(readout.editorID == "M16GuardSleep")
        #expect(readout.procedure == .sleep)
    }

    /// Step 7 — the other way a fight ends. Giving up does not clear a quarrel,
    /// so the same guard re-engages the moment it perceives the player again.
    /// Wounding it mid-fight then makes it run rather than swing: two exits from
    /// one fight, both reached from the same machine.
    ///
    /// The order matters and is the machine's own rule rather than a convenience
    /// here — an actor already under the flee threshold never *starts* a fight,
    /// which is what stops one that just ran from turning around the moment it
    /// looks back. So the guard has to be engaged before it can be wounded into
    /// running.
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

        // Running does not go on forever: past the break distance the pursuit
        // ends the same way a finished search does. The distance is opened here
        // by moving the player rather than by letting the guard run, because
        // this arena's two navmesh sheets are 200 units long and the flee
        // distance is 1,400 — the mover has nowhere to take it, which is a
        // property of the fixture and not of the machine. What is being checked
        // is that the *break* is a distance test the machine applies, and it is
        // symmetric in who opened the gap.
        chain.playerFeet = chain.guardFeet
            + SIMD3(CombatBehaviorSettings.standard.fleeBreakDistance + 100, 0, 0)
        #expect(
            chain.run(frames: 600) { chain.combat.phase(of: Chain.guardKey) == .disengaged },
            "the guard stayed in a fight with a player two thousand units away"
        )
        #expect(chain.packageResumes.count == 2, "the second exit handed it back too")
    }

    /// The whole arc, stated once: every phase the milestone claims an actor
    /// passes through was actually entered by the machine on its own clock.
    ///
    /// `contact` is asserted through the machine's own count rather than through
    /// the observed set, and that is not a weaker check. The contact phase is
    /// exactly one fixed step long — which is what makes a hit land once rather
    /// than once per frame of the swing — and the route samples the phase once
    /// per frame, so a frame that drove two steps can step through contact
    /// without the sample ever seeing it. The count cannot miss it.
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

    private typealias Chain = M16AcceptanceChain
}
