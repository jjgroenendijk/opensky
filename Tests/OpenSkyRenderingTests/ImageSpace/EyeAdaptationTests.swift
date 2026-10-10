// The tone-mapping eye: the first measurement sets it, later ones pull it at the
// IMGS speed, and the exposure brightens a dark scene by the IMGS strength.

@testable import OpenSkyRendering
import Testing

struct EyeAdaptationTests {
    @Test func theFirstMeasurementSetsTheEyeAndLaterOnesPullIt() throws {
        var eye = EyeAdaptation()
        eye.advance(measured: 0.05, speed: 40, deltaTime: 1 / 60)
        #expect(eye.adaptedLuminance == 0.05)

        eye.advance(measured: 0.5, speed: 40, deltaTime: 0.1)
        let adapted = try #require(eye.adaptedLuminance)
        #expect(adapted > 0.05 && adapted < 0.5)

        eye.advance(measured: 0.5, speed: 0, deltaTime: 0.1)
        #expect(eye.adaptedLuminance == 0.5)
    }

    @Test func aDarkSceneGetsMoreExposureAtAStrongerStrength() {
        var eye = EyeAdaptation()
        #expect(eye.exposure(strength: 15) == 1)
        eye.advance(measured: 0.02, speed: 40, deltaTime: 0)
        let weak = eye.exposure(strength: 1)
        let strong = eye.exposure(strength: 25)
        #expect(weak > 1 && strong > weak)
        #expect(strong <= EyeAdaptation.exposureRange.upperBound)
        #expect(eye.exposure(strength: 0) == 1)
    }

    @Test func badMeasurementsAreIgnored() {
        var eye = EyeAdaptation()
        eye.advance(measured: .nan, speed: 40, deltaTime: 0.1)
        eye.advance(measured: 0, speed: 40, deltaTime: 0.1)
        #expect(eye.adaptedLuminance == nil)
    }

    @Test func theMeanComesBackFromTheFixedPointLogSum() throws {
        // Two samples of luminance 0.25: log2 is -2, so each adds (16 - 2) * 256.
        let sum = UInt32(2 * (16 - 2) * 256)
        let mean = try #require(ToneMappingState.meanLuminance(sum: sum, count: 2))
        #expect(abs(mean - 0.25) < 1e-5)
        #expect(ToneMappingState.meanLuminance(sum: 0, count: 0) == nil)
    }
}
