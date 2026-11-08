// The tone-mapping eye: the first measurement sets both channels, later ones pull them
// at the IMGS rates, and the exposure is their ratio, so a steady scene returns to 1.

@testable import OpenSkyRenderCore
import Testing

struct EyeAdaptationTests {
    @Test func theFirstMeasurementSetsTheEyeAndLaterOnesPullIt() throws {
        var eye = EyeAdaptation()
        eye.advance(measured: 0.05, speed: 3, strength: 3, deltaTime: 1 / 60)
        #expect(eye.adaptedLuminance == 0.05 && eye.exposure == 1)

        eye.advance(measured: 0.5, speed: 3, strength: 3, deltaTime: 1 / 30)
        let slow = try #require(eye.adaptedLuminance)
        let fast = try #require(eye.fastLuminance)
        // Speed 3 and strength 3: X closes 5 % of the gap per 1/30 s and Y 6 %.
        #expect(abs(slow - (0.05 + 0.45 * 0.05)) < 1e-5)
        #expect(abs(fast - (0.05 + 0.45 * 0.06)) < 1e-5)
        #expect(eye.exposure > 1)
    }

    @Test func aSteadySceneReturnsToExposureOne() {
        var eye = EyeAdaptation()
        eye.advance(measured: 0.02, speed: 3, strength: 3, deltaTime: 0)
        eye.advance(measured: 0.4, speed: 3, strength: 3, deltaTime: 1 / 30)
        for _ in 0 ..< 2000 {
            eye.advance(measured: 0.4, speed: 3, strength: 3, deltaTime: 1 / 30)
        }
        #expect(eye.adaptedLuminance == 0.4 && eye.fastLuminance == 0.4)
        #expect(eye.exposure == 1)
    }

    @Test func aSmallGapClosesByTheMinimumStepWithoutPassingIt() {
        #expect(EyeAdaptation.chase(0.5, 0.501, rate: 0.01) == 0.501)
        #expect(EyeAdaptation.chase(0.5, 0.4, rate: 0.01) == 0.5 - EyeAdaptation.minimumStep)
        #expect(EyeAdaptation.chase(0.5, 0.4, rate: 0) == 0.5)
    }

    @Test func badMeasurementsAreIgnored() {
        var eye = EyeAdaptation()
        eye.advance(measured: .nan, speed: 3, strength: 3, deltaTime: 0.1)
        #expect(eye.adaptedLuminance == nil && eye.exposure == 1)
    }

    @Test func theMeanComesBackFromTheFixedPointSum() throws {
        let sum = UInt32(2 * 0.25 * ToneMappingState.fixedPointScale)
        let mean = try #require(ToneMappingState.meanLuminance(sum: sum, count: 2))
        #expect(abs(mean - 0.25) < 1e-5)
        #expect(ToneMappingState.meanLuminance(sum: 0, count: 0) == nil)
    }
}
