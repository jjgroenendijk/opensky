// Confidence decides who breaks off and who fights; Assistance decides whom an actor helps.
// The numbers are OpenSky's reading of the AI Data tab's words.

@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPerceptionInterface
import Testing

@MainActor
struct CombatTemperamentTests {
    private typealias Fixture = CombatBehaviorFixture

    private func temperament(_ confidence: Float, strength: Float) -> CombatTemperament {
        CombatTemperament(confidence: confidence, strengthRatio: strength)
    }

    @Test func eachConfidenceBreaksOffBelowItsOwnStrength() {
        #expect(temperament(0, strength: 10).breaksOff)
        #expect(!temperament(4, strength: 0.01).breaksOff)
        #expect(temperament(1, strength: 0.9).breaksOff)
        #expect(!temperament(1, strength: 1.1).breaksOff)
        #expect(temperament(2, strength: 0.4).breaksOff)
        #expect(!temperament(2, strength: 0.6).breaksOff)
        #expect(temperament(3, strength: 0.2).breaksOff)
        #expect(!temperament(3, strength: 0.3).breaksOff)
    }

    @Test func aLowLevelActorAtFullHealthStillFightsAStrongerTarget() {
        let ratio = CombatTemperament.strengthRatio(
            level: 1, healthFraction: 1, targetLevel: 40, targetHealthFraction: 1
        )
        #expect(abs(ratio - Float(0.5).squareRoot()) < 0.001)
        #expect(!temperament(2, strength: ratio).breaksOff)
    }

    @Test func theModifierIsFixedPerActorAndInRange() {
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x1234)
        let modifier = CombatTemperament.modifier(for: key)
        #expect(modifier == CombatTemperament.modifier(for: key))
        #expect(CombatTemperament.modifierRange.contains(modifier))
    }

    @Test func aCowardFleesOnSightInsteadOfStartingAFight() {
        var machine = Fixture.machine()
        var inputs = Fixture.inputs()
        inputs.temperament = temperament(0, strength: 5)
        let step = machine.step(seconds: Fixture.step, inputs: inputs)
        #expect(step.phase == .fleeing)
    }

    @Test func aFoolhardyActorFightsOnWhenNearlyDead() {
        var machine = Fixture.machine()
        Fixture.run(&machine, seconds: 1, inputs: Fixture.inputs())
        var hurt = Fixture.inputs(healthFraction: 0.05)
        hurt.temperament = temperament(4, strength: 0.05)
        let step = machine.step(seconds: Fixture.step, inputs: hurt)
        #expect(step.phase != .fleeing)
    }

    @Test func assistanceHelpsOnlyTheReactionsItNames() {
        #expect(!CombatAssistance(value: 0).helps(.ally))
        #expect(CombatAssistance(value: 1).helps(.ally))
        #expect(!CombatAssistance(value: 1).helps(.friend))
        #expect(CombatAssistance(value: 2).helps(.friend))
        #expect(!CombatAssistance(value: 2).helps(.neutral))
    }
}
