// The attack chance an actor with a combat style rolls in reach, and how often it rolls.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import Testing

@MainActor
struct CombatAttackChanceTests {
    private typealias Fixture = CombatBehaviorFixture

    private static func settings(chance: Float) -> CombatBehaviorSettings {
        var settings = Fixture.neverCasting
        settings.attackChance = chance
        return settings
    }

    @Test func theStyleSetsTheChanceFromItsOffensiveValue() {
        let neutral = CombatStyleTuning.neutral
        #expect(abs(neutral.attackChance() - 0.525) < 0.0001)
        var tuning = neutral
        tuning.offensiveMultiplier = .nan
        #expect(abs(tuning.attackChance() - 0.525) < 0.0001)
        tuning.attackWeights.attackStaggered = 2
        tuning.attackWeights.powerAttackStaggered = 3
        let settings = CombatBehaviorSettings.standard.tuned(by: tuning)
        let chance = settings.attackChance ?? 0
        #expect(abs(chance - 0.525) < 0.0001)
        #expect(settings.staggeredAttackMult == 3)
        #expect(CombatBehaviorSettings.standard.attackChance == nil)
    }

    @Test func aStaggeredTargetAndTheTimeSinceTheLastHitRaiseTheChance() {
        var machine = Fixture.machine(settings: Self.settings(chance: 0.5))
        var inputs = Fixture.inputs()
        #expect(machine.attackChance(inputs) == 0.5)
        machine.secondsSinceShot = 2
        #expect(abs(machine.attackChance(inputs) - 0.6) < 0.0001)
        machine.secondsSinceShot = 9
        #expect(abs(machine.attackChance(inputs) - 0.75) < 0.0001)
        var settings = Self.settings(chance: 0.5)
        settings.staggeredAttackMult = 2
        machine = Fixture.machine(settings: settings)
        inputs.targetIsStaggered = true
        #expect(machine.attackChance(inputs) == 1)
    }

    @Test func aFailedRollWaitsAQuarterSecondBeforeTheNext() {
        var machine = Fixture.machine(settings: Self.settings(chance: 0))
        let inputs = Fixture.inputs()
        let first = machine.rollsAttack(inputs)
        #expect(!first)
        #expect(machine.nextAttackRoll == 0.25)
        let second = machine.rollsAttack(inputs)
        #expect(!second)
        #expect(machine.nextAttackRoll == 0.25)
    }

    @Test func anActorWithAChanceOfZeroNeverSwingsAndOneOfOneSwingsAtOnce() {
        var never = Fixture.machine(settings: Self.settings(chance: 0))
        let idle = Fixture.run(&never, seconds: 4, inputs: Fixture.inputs())
        let swung = idle.filter(\.startedAttack).count
        #expect(swung == 0)
        #expect(never.phase == .spacing)

        var always = Fixture.machine(settings: Self.settings(chance: 1))
        Fixture.run(&always, until: { $0.phase == .spacing }, inputs: Fixture.inputs())
        let next = always.step(seconds: Fixture.step, inputs: Fixture.inputs())
        #expect(next.startedAttack)
    }
}
