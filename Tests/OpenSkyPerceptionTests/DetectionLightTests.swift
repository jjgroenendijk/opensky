// The light level a target reads: ambient, directional, and point lights with
// the shader's falloff, as a fraction of the full-light luminance.

@testable import OpenSkyPerception
import simd
import Testing

struct DetectionLightTests {
    private let origin = SIMD3<Float>(0, 0, 0)

    @Test func ambientAndDirectionalAddAsLuminance() {
        let sample = DetectionLightSample(
            ambient: SIMD3(repeating: 0.1), directional: SIMD3(repeating: 0.3), pointLights: []
        )
        #expect(abs(sample.luminance(at: origin) - 0.4) < 1e-5)
        #expect(abs(sample.level(at: origin, fullLuminance: 1) - 0.4) < 1e-5)
        #expect(abs(sample.level(at: origin, fullLuminance: 0.2) - 1) < 1e-5)
    }

    @Test func aPointLightFallsOffToNothingAtItsRadius() {
        let torch = DetectionPointLight(
            position: SIMD3(0, 0, 0), radius: 200, colour: SIMD3(repeating: 1), falloffExponent: 1
        )
        let sample = DetectionLightSample(ambient: .zero, directional: .zero, pointLights: [torch])
        #expect(abs(sample.luminance(at: origin) - 1) < 1e-5)
        #expect(abs(sample.luminance(at: SIMD3(100, 0, 0)) - 0.5) < 1e-5)
        #expect(sample.luminance(at: SIMD3(250, 0, 0)) == 0)
    }

    @Test func badInputGivesAFiniteLevel() {
        let sample = DetectionLightSample(
            ambient: SIMD3(repeating: .nan), directional: .zero, pointLights: []
        )
        #expect(sample.luminance(at: origin) == 0)
        #expect(sample.level(at: origin, fullLuminance: 0) == 1)
    }
}
