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
        #expect(temperament(1, strength: 0.3).breaksOff)
        #expect(!temperament(1, strength: 0.45).breaksOff)
        #expect(temperament(2, strength: 0.1).breaksOff)
        #expect(!temperament(2, strength: 0.2).breaksOff)
        #expect(temperament(3, strength: 0.03).breaksOff)
        #expect(!temperament(3, strength: 0.05).breaksOff)
    }

    @Test func aNudgedConfidenceBlendsTheTwoLevelsAroundIt() {
        let settings = CombatAISettings.vanilla
        let halfway = settings.breakOffStrength(confidence: 1.5)
        #expect(abs(halfway - (0.375 + 0.15) / 2) < 0.0001)
        #expect(settings.breakOffStrength(confidence: 5) == 0.0375)
        #expect(settings.confidenceModifierRange == -0.25 ... 1)
    }

    @Test func theFleeAndFollowDistancesComeFromTheSettings() {
        let settings = CombatAISettings.vanilla
        let fled = settings.applyingFlee(to: .standard, interior: true)
        #expect(fled.fleeDistance == 3000)
        #expect(fled.fleeBreakDistance == 3400)
        #expect(settings.fleeDistance(interior: false) == 5000)
        #expect(settings.followDistance(leaderIsPlayer: true) == 423)
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
