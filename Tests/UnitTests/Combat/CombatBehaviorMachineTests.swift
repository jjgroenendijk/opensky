// One actor's combat mind: entry, approach and the attack cadence (issue #424,
// roadmap item 16.7).
//
// The machine is a pure value over a fixed step, so every case below is a
// sequence of steps and an assertion on the phase and the commands that came
// out. What it does *not* touch is the world: `CombatLoopRuntimeTests` owns the
// half where a decision becomes a hit, a path request or a package resumption,
// and `CombatBehaviorRetreatTests` owns fleeing, searching and giving up.
//
// This is what replaced `DevTargetDriverTests`, which pinned the clock's four
// phases. The cadence cases are the same assertions against the same numbers;
// everything else is behaviour the clock could not have.

@testable import opensky
import simd
import Testing

@MainActor
struct CombatBehaviorMachineTests {
    private typealias Fixture = CombatBehaviorFixture

    // MARK: - Entry

    @Test func anUnperceivedTargetLeavesTheActorIdle() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 5, inputs: Fixture.inputs(state: .unaware, lastKnown: nil))
        #expect(machine.phase == .idle)
        #expect(machine.fightCount == 0)
        #expect(!machine.isEngaged)
    }

    @Test func suspicionAloneIsNotEnoughToStartAFight() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 5, inputs: Fixture.inputs(state: .suspicious))
        #expect(machine.phase == .idle)
    }

    @Test func perceivingTheTargetStartsTheFightAndAsksForAnApproach() {
        var machine = Fixture.machine()
        let first = machine.step(seconds: Fixture.step, inputs: Fixture.inputs(distance: 4000))
        #expect(first.startedFight)
        #expect(first.phase == .approaching)
        #expect(first.command == .approach(SIMD3(0, 0, 0)))
        #expect(machine.fightCount == 1)
    }

    @Test func aScriptEngagesTheActorWithoutItPerceivingAnything() {
        var machine = Fixture.machine()
        let first = machine.step(
            seconds: Fixture.step,
            inputs: Fixture.inputs(state: .unaware, lastKnown: nil, isForced: true)
        )
        #expect(first.startedFight)
        #expect(machine.isEngaged)
    }

    // MARK: - Approach and spacing

    @Test func theActorApproachesUntilItIsInsideItsOwnReach() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 2, inputs: Fixture.inputs(distance: 4000))
        #expect(machine.phase == .approaching)

        _ = machine.step(seconds: Fixture.step, inputs: Fixture.inputs(distance: Fixture.inReach))
        #expect(machine.phase == .spacing || machine.phase == .blocking)
    }

    @Test func aTargetThatWalksOutOfReachIsChasedAgain() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        #expect(machine.phase != .approaching)

        let away = machine.step(seconds: Fixture.step, inputs: Fixture.inputs(distance: 4000))
        #expect(away.phase == .approaching)
        #expect(away.command == .approach(SIMD3(0, 0, 0)))
    }

    @Test func anApproachRepathsOnTheStatedIntervalRatherThanEveryStep() {
        var machine = Fixture.machine()
        let steps = Fixture.run(&machine, seconds: 2.05, inputs: Fixture.inputs(distance: 4000))
        let commands = steps.compactMap(\.command).count
        // One at entry, then one per interval over the two seconds that follow.
        #expect(commands == 1 + Int(2 / Fixture.settings.commandIntervalSeconds))
    }

    // MARK: - The attack cadence

    @Test func theAttackRunsWindupContactRecoveryInThatOrder() {
        var machine = Fixture.machine(settings: Fixture.unblocking)
        let toWindup = Fixture.run(
            &machine, until: { $0.phase == .windup }, inputs: Fixture.inputs()
        )
        #expect(toWindup.last?.startedAttack == true)
        #expect(machine.attackCount == 1)

        let toContact = Fixture.run(
            &machine, until: { $0.phase == .contact }, inputs: Fixture.inputs()
        )
        #expect(toContact.last?.reachedContact == true)
        #expect(machine.contactCount == 1)

        _ = machine.step(seconds: Fixture.step, inputs: Fixture.inputs())
        #expect(machine.phase == .recovery)

        Fixture.run(&machine, until: { $0.phase != .recovery }, inputs: Fixture.inputs())
        #expect(machine.phase == .spacing || machine.phase == .blocking)
    }

    @Test func exactlyOneContactStepIsReportedPerAttack() {
        var machine = Fixture.machine(settings: Fixture.unblocking)
        let steps = Fixture.run(&machine, seconds: 4, inputs: Fixture.inputs())
        let contacts = steps.filter(\.reachedContact).count
        #expect(contacts == machine.contactCount)
        #expect(contacts >= 1)
    }

    // MARK: - Blocking

    @Test func anActorThatAlwaysRollsABlockRaisesItsGuardBeforeAttacking() {
        var machine = Fixture.machine(settings: Fixture.alwaysBlocking)
        let steps = Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        #expect(steps.contains { $0.raisedBlock })
        #expect(machine.phase == .blocking)
        #expect(machine.blockKind == .weapon)
        #expect(machine.blockCount == 1)
    }

    @Test func anActorThatNeverRollsABlockKeepsItsGuardDown() {
        var machine = Fixture.machine(settings: Fixture.unblocking)
        let steps = Fixture.run(&machine, seconds: 6, inputs: Fixture.inputs())
        #expect(!steps.contains { $0.raisedBlock })
        #expect(machine.blockCount == 0)
        #expect(machine.blockKind == nil)
    }

    @Test func aRaisedGuardBecomesAnAttackWhenItsTimeIsUp() {
        var machine = Fixture.machine(settings: Fixture.alwaysBlocking)
        Fixture.run(&machine, until: { $0.phase == .blocking }, inputs: Fixture.inputs())
        #expect(machine.phase == .blocking)

        Fixture.run(&machine, until: { $0.phase != .blocking }, inputs: Fixture.inputs())
        #expect(machine.phase == .windup)
    }

    // MARK: - Stagger

    @Test func aStaggerTakesTheAttackAwayAndReturnsToTheGap() {
        var machine = Fixture.machine(settings: Fixture.unblocking)
        Fixture.run(&machine, until: { $0.phase == .windup }, inputs: Fixture.inputs())
        #expect(machine.phase == .windup)

        // Bound rather than called inside `#expect`: the macro captures its
        // expression in an escaping closure, which cannot mutate the machine.
        let staggered = machine.stagger()
        let again = machine.stagger()
        #expect(staggered)
        #expect(!again)
        #expect(machine.phase == .staggered)

        Fixture.run(&machine, until: { $0.phase != .staggered }, inputs: Fixture.inputs())
        #expect(machine.phase == .spacing)
        // The interrupted attack was started and never connected, which is
        // exactly the difference between the two counts.
        #expect(machine.attackCount == 1)
        #expect(machine.contactCount == 0)
    }

    @Test func staggeringAnActorThatWasNotFightingPutsItInTheFight() {
        var machine = Fixture.machine()
        let staggered = machine.stagger()
        #expect(staggered)
        #expect(machine.isEngaged)
        #expect(machine.fightCount == 1)
    }
}
