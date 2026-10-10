// Pure samplers behind particle draw order, mesh emitters, and light animation.

import Foundation
@testable import OpenSkyFormatsMesh
@testable import OpenSkyRendering
import simd
import Testing

struct LivingEnvironmentSamplingTests {
    @Test func backToFrontPutsFarFirstAndKeepsTies() {
        let points: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(5, 0, 0), SIMD3(-1, 0, 0)]
        let ordered = ParticleDrawOrder.backToFront(points, viewer: .zero) { $0 }
        #expect(ordered == [SIMD3(5, 0, 0), SIMD3(1, 0, 0), SIMD3(-1, 0, 0)])
    }

    @Test func meshSamplerUsesFaceCentreAndFaceNormal() {
        let source = MeshEmitterSource(
            meshRefs: [], velocity: .normals, emitFrom: .faceCenter, emissionAxis: .zero,
            positions: [SIMD3(0, 0, 0), SIMD3(3, 0, 0), SIMD3(0, 3, 0)],
            triangles: [SIMD3(0, 1, 2)]
        )
        let point = MeshEmitterSampler(source: source).sample { 0 }
        #expect(simd_distance(point.position, SIMD3(1, 1, 0)) < 1e-5)
        #expect(point.normal == SIMD3(0, 0, 1))
    }

    @Test func meshSamplerWithoutGeometryUsesOrigin() {
        let source = MeshEmitterSource(
            meshRefs: [], velocity: .random, emitFrom: .faceSurface, emissionAxis: .zero
        )
        #expect(MeshEmitterSampler(source: source).sample { 0.5 }.position == .zero)
    }

    @Test func pulseSwingsAroundBaseBrightness() {
        let pulse = RenderLightAnimation(
            kind: .pulse, period: 2, intensityAmplitude: 0.5, movementAmplitude: 0, phase: 0
        )
        #expect(abs(pulse.sample(at: 0.5).intensity - 1.5) < 1e-5)
        #expect(abs(pulse.sample(at: 1.5).intensity - 0.5) < 1e-5)
    }

    @Test func flickerStaysInRangeAndRepeats() {
        let flicker = RenderLightAnimation(
            kind: .flicker, period: 0.3, intensityAmplitude: 0.4, movementAmplitude: 2, phase: 0.25
        )
        for step in 0 ..< 50 {
            let sample = flicker.sample(at: Float(step) * 0.07)
            #expect(sample.intensity >= 0.6 - 1e-4 && sample.intensity <= 1.4 + 1e-4)
            #expect(simd_reduce_max(abs(sample.offset)) <= 2 + 1e-4)
        }
        #expect(flicker.sample(at: 1.3) == flicker.sample(at: 1.3))
    }
}
