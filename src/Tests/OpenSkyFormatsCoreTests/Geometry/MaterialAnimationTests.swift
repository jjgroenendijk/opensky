// Material animation tracks: the controller clock's cycle types, and which material
// value each target changes (docs/formats/nif-controllers.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct MaterialAnimationTests {
    private func clock(_ cycle: ControllerClock.Cycle) -> ControllerClock {
        ControllerClock(cycle: cycle, frequency: 1, phase: 0, startTime: 0, stopTime: 2)
    }

    @Test func eachCycleMapsTimeIntoTheKeyRange() {
        #expect(clock(.loop).time(at: 2.5) == 0.5)
        #expect(clock(.reverse).time(at: 2.5) == 1.5)
        #expect(clock(.clamp).time(at: 2.5) == 2)
    }

    @Test func aLoopingUOffsetTrackScrollsTheTexture() {
        let track = MaterialAnimation.Track(
            target: .uOffset, clock: clock(.loop), times: [0, 2], values: [.zero, SIMD3(1, 0, 0)]
        )
        let animation = MaterialAnimation(tracks: [track])
        let moved = Material.fallback.animated(by: animation, at: 3)
        #expect(moved.uvOffset == SIMD2(0.5, 0))
        #expect(moved.uvScale == Material.fallback.uvScale)
    }

    @Test func effectAlphaAndEmissiveGoToTheEffectBaseColour() {
        let effect = EffectShading(
            baseColor: SIMD4(1, 1, 1, 1), baseColorScale: 1, paletteTexture: nil,
            paletteColor: false, paletteAlpha: false, falloff: nil, vertexColors: false,
            vertexAlpha: false
        )
        let base = Material(
            diffuseTexture: nil, normalTexture: nil, uvOffset: .zero, uvScale: SIMD2(1, 1),
            alpha: 1, glossiness: 1, specularColor: .one, specularStrength: 1, doubleSided: false,
            alphaBlend: true, alphaTestThreshold: nil, effect: effect
        )
        let tracks = [
            MaterialAnimation.Track(
                target: .alpha, clock: clock(.clamp), times: [0], values: [SIMD3(0.25, 0, 0)]
            ),
            MaterialAnimation.Track(
                target: .emissiveColor, clock: clock(.clamp), times: [0], values: [SIMD3(1, 0, 0)]
            ),
            MaterialAnimation.Track(
                target: .falloffStopOpacity, clock: clock(.clamp), times: [0],
                values: [SIMD3(0.5, 0, 0)]
            )
        ]
        let moved = base.animated(by: MaterialAnimation(tracks: tracks), at: 1)
        #expect(moved.effect?.baseColor == SIMD4(1, 0, 0, 0.25))
        #expect(moved.effect?.falloff == SIMD4(1, 0, 1, 0.5))
        #expect(moved.alpha == 1, "an effect keeps its alpha in the base colour")
    }
}
