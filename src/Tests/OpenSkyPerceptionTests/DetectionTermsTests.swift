// The light level, alert, sleep, player, and flying terms of the detection formula
// (CK wiki "Category:Detection"), with the install's values from `synthetic`.

@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
import OpenSkyPhysics
import Testing

struct DetectionTermsTests {
    private let settings = DetectionSettings.synthetic

    @Test func anInteriorAddsItsLightModBeforeTheCap() {
        let inside = DetectionInputs(
            distance: 0, isExterior: false, traits: DetectionTargetTraits(lightLevel: 0.5)
        )
        #expect(DetectionFormula.lightLevel(inputs: inside, settings: settings) == 75)
        // No exterior halving indoors.
        let visual = DetectionFormula.visualFactor(inputs: inside, settings: settings)
        #expect(abs(visual - 90 * 0.33) < 1e-4)
        let outside = DetectionInputs(distance: 0, traits: DetectionTargetTraits(lightLevel: 0.5))
        #expect(DetectionFormula.lightLevel(inputs: outside, settings: settings) == 50)
    }

    @Test func alertAndSleepWeightTheNoticerSkill() {
        var tuned = settings
        tuned.alertMod = MovementSetting(value: 1, source: "test")
        tuned.sleepBonus = MovementSetting(value: -0.5, source: "test")
        var inputs = DetectionInputs(distance: 0, noticerSkill: 40)
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: tuned) == 20)
        inputs.observer.isAlert = true
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: tuned) == 40)
        inputs.observer = DetectionObserverState(isSleeping: true)
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: tuned) == 10)
        // The install sets both to 0, so vanilla observers are unchanged.
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: settings) == 20)
    }

    @Test func aSleepingObserverSeesNothing() {
        var inputs = DetectionInputs(distance: 0)
        #expect(DetectionFormula.visualFactor(inputs: inputs, settings: settings) > 0)
        inputs.observer.isSleeping = true
        #expect(DetectionFormula.visualFactor(inputs: inputs, settings: settings) == 0)
    }

    @Test func thePlayerSneakerFactorUsesThePlayerDetectionSettings() {
        var inputs = DetectionInputs(distance: 0, traits: DetectionTargetTraits(sneakSkill: 50))
        #expect(DetectionFormula.sneakerFactor(inputs: inputs, settings: settings) == 25)
        inputs.isPlayerTarget = true
        #expect(DetectionFormula.sneakerFactor(inputs: inputs, settings: settings) == 30)
    }

    @Test func thePlayerValueNeverFallsBelowTheFloor() {
        var inputs = DetectionInputs(
            distance: 0, hasLineOfSight: false,
            traits: DetectionTargetTraits(sneakSkill: 100), noticerSkill: 0
        )
        inputs.isPlayerTarget = true
        #expect(DetectionFormula.breakdown(inputs: inputs, settings: settings).value == -30)
    }

    @Test func aFlyingObserverReachesFurther() {
        let ground = DetectionFormula.maximumDistance(settings: settings, isExterior: false)
        let flying = DetectionFormula.maximumDistance(
            settings: settings, isExterior: false, isFlying: true
        )
        #expect(flying == ground * 3)
    }

    @Test func anAttackOrADetectionEventHoldsTheRefill() {
        let stealth = StealthPointSettings.vanilla
        var pool = StealthPointPool(settings: stealth)
        pool.advance(highestValue: 10, overThreshold: false, by: 1, settings: stealth)
        pool.holdRefill(for: stealth.attackedWait)
        #expect(pool.refillWait == 15)
        pool.holdRefill(for: stealth.detectedEventWait)
        #expect(pool.refillWait == 15)
        pool.advance(highestValue: -10, overThreshold: false, by: 14, settings: stealth)
        let drained = pool.points
        pool.advance(highestValue: -10, overThreshold: false, by: 0.5, settings: stealth)
        #expect(pool.points == drained)
    }

    @Test func movementMakesATargetEasierToSee() {
        let still = DetectionInputs(distance: 0)
        let base = DetectionFormula.visualFactor(inputs: still, settings: settings)
        let walking = DetectionInputs(distance: 0, gait: .walk)
        let running = DetectionInputs(distance: 0, gait: .sprint)
        let walk = DetectionFormula.visualFactor(inputs: walking, settings: settings)
        let run = DetectionFormula.visualFactor(inputs: running, settings: settings)
        #expect(abs(walk - base * 1.01) < 1e-4)
        #expect(abs(run - base * 1.21) < 1e-4)
    }

    @Test func blindnessDimsTheObserversSight() {
        var inputs = DetectionInputs(distance: 0)
        let clear = DetectionFormula.visualFactor(inputs: inputs, settings: settings)
        inputs.observer.blindness = 25.9
        let dim = DetectionFormula.visualFactor(inputs: inputs, settings: settings)
        #expect(abs(dim - clear * 0.75) < 1e-4)
        inputs.observer.blindness = 100
        #expect(DetectionFormula.visualFactor(inputs: inputs, settings: settings) == 0)
    }

    @Test func invisibilityScalesSightByTheStealthBoySetting() {
        let inputs = DetectionInputs(distance: 0, traits: DetectionTargetTraits(isInvisible: true))
        #expect(DetectionFormula.visualFactor(inputs: inputs, settings: settings) == 0)
        var tuned = settings
        tuned.stealthBoyMult = MovementSetting(value: 0.5, source: "test")
        let visible = DetectionFormula.visualFactor(
            inputs: DetectionInputs(distance: 0), settings: tuned
        )
        let half = DetectionFormula.visualFactor(inputs: inputs, settings: tuned)
        #expect(abs(half - visible * 0.5) < 1e-4)
    }

    @Test func anObserverFightingSomeoneElseNoticesLess() {
        var inputs = DetectionInputs(distance: 0, noticerSkill: 40)
        inputs.observer.isFightingAnother = true
        #expect(abs(DetectionFormula.noticerFactor(inputs: inputs, settings: settings) - 12) < 1e-4)
    }
}
