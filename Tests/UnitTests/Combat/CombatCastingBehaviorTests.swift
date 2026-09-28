// One actor's combat mind, casting half (issue #473, roadmap item 19.10): when
// a fighter chooses a spell over a swing, which spell it chooses, how long it
// holds it, and what happens when it cannot afford one.
//
// A third file of cases against `CombatBehaviorMachine` rather than more cases
// in the cadence or the retreat suite, for the reason those two are separate:
// the machine is one type whose behaviour is larger than the strict lint type
// cap, and the fixture both halves share already lives beside them.
//
// Every case is a sequence of fixed steps and an assertion on the phase and the
// step flags that came out. The world half — a cast that becomes spent magicka
// and a projectile — is `CombatLoopCastingTests`.

@testable import opensky
import simd
import Testing

@MainActor
struct CombatCastingBehaviorTests {
    private typealias Fixture = CombatBehaviorFixture

    /// Steps until the machine is in `phase`, so a case asserts on a transition
    /// rather than on a step count it would have to re-derive.
    @discardableResult
    private func run(
        _ machine: inout CombatBehaviorMachine,
        toward phase: CombatBehaviorPhase,
        inputs: CombatBehaviorInputs
    ) -> [CombatBehaviorStep] {
        CombatBehaviorFixture.run(
            &machine,
            until: { $0.phase == phase },
            inputs: inputs
        )
    }

    // MARK: - Choosing to cast

    @Test func aCasterOutOfWeaponReachCastsInsteadOfClosing() {
        var machine = Fixture.machine(settings: Fixture.neverCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        let steps = run(&machine, toward: .casting, inputs: inputs)
        #expect(machine.phase == .casting)
        #expect(machine.castCount == 1)
        #expect(steps.last?.startedCast == Fixture.fireball)
        // It stopped walking to cast rather than carrying on toward the target.
        #expect(steps.last?.command == .hold)
    }

    @Test func aCasterInsideWeaponReachCastsOnTheRoll() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        #expect(machine.phase == .casting)
        #expect(machine.attackCount == 0)
    }

    @Test func aCasterThatRolledAgainstItSwingsInstead() {
        var machine = Fixture.machine(settings: Fixture.neverCasting)
        let inputs = Fixture.inputs(
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .windup, inputs: inputs)
        #expect(machine.phase == .windup)
        #expect(machine.castCount == 0)
        #expect(machine.attackCount == 1)
    }

    // MARK: - The affordability and range gates

    @Test func aSpellNobodyCanPayForIsNotCast() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 5, [Fixture.fireball])
        )
        Fixture.run(&machine, seconds: 5, inputs: inputs)
        #expect(machine.castCount == 0)
        // Out of magicka is not out of the fight: it closes to swing instead.
        #expect(machine.phase == .approaching)
    }

    @Test func aSpellThatDoesNotReachIsNotCast() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 2000,
            casting: Fixture.casting(magicka: 100, [Fixture.flames])
        )
        Fixture.run(&machine, seconds: 5, inputs: inputs)
        #expect(machine.castCount == 0)
        #expect(machine.phase == .approaching)
    }

    @Test func theCostliestAffordableSpellInRangeIsChosen() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(
                magicka: 100, [Fixture.fireball, Fixture.firestorm, Fixture.flames]
            )
        )
        let steps = run(&machine, toward: .casting, inputs: inputs)
        #expect(steps.last?.startedCast == Fixture.firestorm)
    }

    @Test func aDrainedCasterFallsBackDownItsOwnSpellList() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 30, [Fixture.fireball, Fixture.firestorm])
        )
        let steps = run(&machine, toward: .casting, inputs: inputs)
        #expect(steps.last?.startedCast == Fixture.fireball)
    }

    // MARK: - Holding and letting go

    @Test func aChargedSpellIsReleasedWhenItsChargeTimeElapses() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        let held = Fixture.run(
            &machine, until: { $0.phase != .casting }, inputs: inputs
        )
        #expect(machine.phase == .recovery)
        #expect(held.last?.releasedCast == Fixture.fireball)
        #expect(held.last?.cancelledCast == false)
        #expect(machine.pendingCast == nil)
        // Charging took at least the record's own charge time.
        #expect(Float(held.count) * Fixture.step >= Fixture.fireball.chargeSeconds)
    }

    @Test func aMaintainedSpellIsHeldForTheStatedDuration() {
        let settings = CombatBehaviorSettings(blockChance: 0, castChance: 1)
        var machine = Fixture.machine(settings: settings)
        let inputs = Fixture.inputs(
            casting: Fixture.casting(magicka: 100, [Fixture.flames])
        )
        run(&machine, toward: .casting, inputs: inputs)
        let held = Fixture.run(
            &machine, until: { $0.phase != .casting }, inputs: inputs
        )
        #expect(held.last?.releasedCast == Fixture.flames)
        #expect(Float(held.count) * Fixture.step >= settings.concentrationSeconds)
    }

    @Test func aCastLeadsBackIntoTheOrdinaryCadence() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        Fixture.run(&machine, until: { $0.phase == .recovery }, inputs: inputs)
        Fixture.run(&machine, until: { $0.castCount == 2 }, inputs: inputs)
        #expect(machine.castCount == 2)
    }

    // MARK: - Interruptions

    @Test func aStaggerTakesTheChargeAway() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        #expect(machine.pendingCast != nil)
        let staggered = machine.stagger()
        #expect(staggered)
        #expect(machine.phase == .staggered)
        #expect(machine.pendingCast == nil)
    }

    @Test func breakingOffMidChargeReportsTheCastAsCancelled() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        let hurt = machine.step(
            seconds: Fixture.step,
            inputs: Fixture.inputs(
                distance: 1200,
                healthFraction: 0.05,
                casting: Fixture.casting(magicka: 100, [Fixture.fireball])
            )
        )
        #expect(machine.phase == .fleeing)
        #expect(hurt.cancelledCast)
        #expect(machine.pendingCast == nil)
    }

    @Test func losingTheTargetMidChargeCancelsTheCast() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        let lost = machine.step(
            seconds: Fixture.step,
            inputs: Fixture.inputs(
                distance: 1200,
                state: .unaware,
                casting: Fixture.casting(magicka: 100, [Fixture.fireball])
            )
        )
        #expect(machine.phase == .searching)
        #expect(lost.cancelledCast)
    }

    @Test func aRefusedCastLandsBackInTheGapBetweenAttacks() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        machine.abandonCast()
        #expect(machine.phase == .spacing)
        #expect(machine.pendingCast == nil)
    }

    @Test func aFightThatStopsMidChargeDropsIt() {
        var machine = Fixture.machine(settings: Fixture.alwaysCasting)
        let inputs = Fixture.inputs(
            distance: 1200,
            casting: Fixture.casting(magicka: 100, [Fixture.fireball])
        )
        run(&machine, toward: .casting, inputs: inputs)
        machine.park()
        #expect(machine.phase == .idle)
        #expect(machine.pendingCast == nil)
    }

    // MARK: - Determinism

    @Test func twoRunsOfTheSameFightCastTheSameSpellsAtTheSameTimes() {
        let inputs = Fixture.inputs(
            casting: Fixture.casting(magicka: 100, [Fixture.fireball, Fixture.flames])
        )
        var first = Fixture.machine()
        var second = Fixture.machine()
        let one = Fixture.run(&first, seconds: 12, inputs: inputs)
        let two = Fixture.run(&second, seconds: 12, inputs: inputs)
        #expect(one.map(\.startedCast) == two.map(\.startedCast))
        #expect(first.castCount == second.castCount)
        #expect(first.castCount > 0)
    }
}
