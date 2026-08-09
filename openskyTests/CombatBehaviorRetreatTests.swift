// One actor's combat mind: breaking off, searching and giving up (issue #424,
// roadmap item 16.7).
//
// The half of the machine that ends a fight rather than running one. Split from
// `CombatBehaviorMachineTests` for the strict lint type cap; the literals both
// halves hand the machine live in `CombatBehaviorFixture`.

@testable import opensky
import simd
import Testing

@MainActor
struct CombatBehaviorRetreatTests {
    private typealias Fixture = CombatBehaviorFixture

    // MARK: - Fleeing

    @Test func lowHealthBreaksOffAlongAPathAwayFromTheTarget() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        #expect(machine.isEngaged)

        let hurt = machine.step(
            seconds: Fixture.step,
            inputs: Fixture.inputs(healthFraction: Fixture.settings.fleeHealthFraction)
        )
        #expect(hurt.phase == .fleeing)
        guard case let .flee(point) = hurt.command else {
            Issue.record("a fleeing actor asks to be somewhere else")
            return
        }
        // Away from the target, which is at the origin.
        #expect(simd_length(point) > Fixture.inReach)
        // Still in the fight, which is what keeps the combat music playing.
        #expect(machine.isEngaged)
    }

    @Test func aFleeingActorLeavesTheFightOnceItIsFarEnoughAway() {
        var machine = Fixture.machine()
        // Healthy first: an actor already under the threshold never starts a
        // fight, which is its own case below.
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        let hurt = Fixture.inputs(healthFraction: 0.1)
        Fixture.run(&machine, until: { $0.phase == .fleeing }, inputs: hurt)
        #expect(machine.phase == .fleeing)

        let far = Fixture.inputs(
            distance: Fixture.settings.fleeBreakDistance + 1, healthFraction: 0.1
        )
        let ended = machine.step(seconds: Fixture.step, inputs: far)
        #expect(ended.endedPursuit)
        #expect(ended.command == .hold)
        #expect(machine.phase == .disengaged)
        #expect(!machine.isEngaged)
    }

    @Test func anActorThatRanDoesNotStartTheFightAgainWhileItIsStillHurt() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        let hurt = Fixture.inputs(healthFraction: 0.1)
        Fixture.run(&machine, until: { $0.phase == .fleeing }, inputs: hurt)
        _ = machine.step(
            seconds: Fixture.step,
            inputs: Fixture.inputs(
                distance: Fixture.settings.fleeBreakDistance + 1, healthFraction: 0.1
            )
        )
        #expect(machine.phase == .disengaged)

        Fixture.run(&machine, seconds: 5, inputs: hurt)
        #expect(machine.phase == .disengaged)
    }

    // MARK: - Losing the target, searching and giving up

    @Test func losingTheTargetSendsTheActorToTheLastPlaceItSawIt() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())

        let remembered = SIMD3<Float>(10, 20, 0)
        let lost = machine.step(
            seconds: Fixture.step,
            inputs: Fixture.inputs(state: .suspicious, lastKnown: remembered)
        )
        #expect(lost.startedSearch)
        #expect(lost.phase == .searching)
        #expect(lost.command == .investigate(remembered))
        #expect(machine.searchCount == 1)
        // Searching is still being in the fight.
        #expect(machine.isEngaged)
    }

    @Test func theSearchEndsInGivingUpAfterTheStatedTime() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        let lost = Fixture.inputs(state: .unaware)
        Fixture.run(&machine, seconds: Fixture.step, inputs: lost)
        #expect(machine.phase == .searching)

        let steps = Fixture.run(&machine, seconds: Fixture.settings.searchSeconds, inputs: lost)
        #expect(steps.contains { $0.endedPursuit })
        #expect(machine.phase == .disengaged)
        #expect(!machine.isEngaged)
    }

    @Test func findingTheTargetAgainMidSearchResumesTheChase() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        Fixture.run(&machine, seconds: Fixture.step, inputs: Fixture.inputs(state: .unaware))
        #expect(machine.phase == .searching)

        let found = machine.step(seconds: Fixture.step, inputs: Fixture.inputs(distance: 4000))
        #expect(found.phase == .approaching)
        #expect(found.command == .approach(SIMD3(0, 0, 0)))
    }

    @Test func aTargetLostWithNothingRememberedGivesUpRatherThanSearchingNowhere() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())

        let lost = machine.step(
            seconds: Fixture.step,
            inputs: Fixture.inputs(state: .unaware, lastKnown: nil)
        )
        #expect(lost.endedPursuit)
        #expect(machine.phase == .disengaged)
        #expect(machine.searchCount == 0)
    }

    @Test func aDeadTargetEndsThePursuit() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())

        let dead = machine.step(seconds: Fixture.step, inputs: Fixture.inputs(isTargetAlive: false))
        #expect(dead.endedPursuit)
        #expect(!machine.isEngaged)
    }

    @Test func perceivingTheTargetAgainAfterGivingUpStartsASecondFight() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        Fixture.run(
            &machine,
            seconds: Fixture.settings.searchSeconds + 1,
            inputs: Fixture.inputs(state: .unaware)
        )
        #expect(machine.phase == .disengaged)

        let again = machine.step(seconds: Fixture.step, inputs: Fixture.inputs())
        #expect(again.startedFight)
        #expect(machine.fightCount == 2)
    }

    // MARK: - Determinism

    @Test func twoMachinesWithTheSameSeedFightIdentically() {
        var first = Fixture.machine()
        var second = Fixture.machine()
        let steps = Fixture.run(&first, seconds: 20, inputs: Fixture.inputs())
        let other = Fixture.run(&second, seconds: 20, inputs: Fixture.inputs())
        #expect(steps == other)
        #expect(first == second)
    }

    @Test func twoMachinesWithDifferentSeedsDoNotBlockInLockstep() {
        // The seeds are the two the first two generated references produce, so
        // this is the real spread rather than an arbitrary pair.
        var first = CombatBehaviorMachine(
            settings: Fixture.settings, seed: CombatBehaviorMachine.seed(for: .generated(1))
        )
        var second = CombatBehaviorMachine(
            settings: Fixture.settings, seed: CombatBehaviorMachine.seed(for: .generated(2))
        )
        Fixture.run(&first, seconds: 30, inputs: Fixture.inputs())
        Fixture.run(&second, seconds: 30, inputs: Fixture.inputs())
        #expect(first.blockCount != second.blockCount)
    }

    @Test func theSeedIsStableAcrossProcessesRatherThanHashed() {
        // Spelled out rather than compared to itself: a `hashValue`-derived
        // seed would pass a same-process comparison and still differ between
        // two runs of the suite.
        #expect(CombatBehaviorMachine.seed(for: .player) == 17_106_172_437_061_548_856)
    }

    @Test func aZeroOrNonFiniteStepAdvancesNothing() {
        var machine = Fixture.machine()
        #expect(machine.step(seconds: 0, inputs: Fixture.inputs()).phase == .idle)
        #expect(machine.step(seconds: -1, inputs: Fixture.inputs()).phase == .idle)
        #expect(machine.step(seconds: .nan, inputs: Fixture.inputs()).phase == .idle)
        #expect(machine.fightCount == 0)
    }

    @Test func parkingEndsTheFightWithoutLosingTheCounts() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 4, inputs: Fixture.inputs())
        let attacks = machine.attackCount
        #expect(attacks > 0)

        machine.park()

        #expect(machine.phase == .idle)
        #expect(machine.attackCount == attacks)
    }
}
