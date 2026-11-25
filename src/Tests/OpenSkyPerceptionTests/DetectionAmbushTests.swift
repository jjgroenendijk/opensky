// The ambush term: an observer that runs an Ambush package notices its ambush target
// more, and hears it as if in line of sight (docs/engine/detection.md#ambush-packages).

@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd
import Testing

struct DetectionAmbushTests {
    private let settings = DetectionSettings.synthetic

    @Test func theAmbushTargetAddsToTheWeightAndOthersAddTheNonTargetValue() {
        var inputs = DetectionInputs(distance: 0, noticerSkill: 40)
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: settings) == 20)
        inputs.observer.ambush = .target
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: settings) == 70)
        inputs.observer.ambush = .other
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: settings) == 20)
        var tuned = settings
        tuned.ambushNonTargetMod = MovementSetting(value: -0.25, source: "test")
        #expect(DetectionFormula.noticerFactor(inputs: inputs, settings: tuned) == 15)
    }

    @Test func theAmbushTargetIsHeardAsIfInLineOfSight() {
        var inputs = DetectionInputs(distance: 0, hasLineOfSight: false, gait: .walk)
        let muffled = DetectionFormula.soundFactor(inputs: inputs, settings: settings)
        inputs.observer.ambush = .target
        let heard = DetectionFormula.soundFactor(inputs: inputs, settings: settings)
        #expect(abs(muffled - heard * settings.soundLosMult.value) < 1e-4)
        #expect(heard > muffled)
    }

    @Test func theAreaMatchesByPlaceOrTakesEveryone() {
        let area = DetectionAmbushArea.within(center: .zero, radius: 100)
        #expect(area.contains(SIMD3(60, 0, 0)))
        #expect(!area.contains(SIMD3(160, 0, 0)))
        #expect(DetectionAmbushArea.everyone.contains(SIMD3(9000, 0, 0)))
        #expect(!DetectionAmbushArea.unmatched.contains(.zero))
    }
}
