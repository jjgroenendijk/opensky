// Race menu face values to chargen TRI weights, vertex positions, and tints.

import OpenSkyFormatsMesh
@testable import OpenSkyWorld
import Testing

struct ChargenMorphsTests {
    @Test
    func slidersPickTheTargetBySign() {
        var morphs = [Float](repeating: 0, count: 19)
        morphs[0] = 0.5
        morphs[1] = -2
        morphs[18] = 1
        let weights = ChargenMorphs.weights(morphs: morphs, parts: [3, -1, 0, 7])
        #expect(weights == [
            "NoseLong": 0.5, "NoseDown": 1, "VampireMorph": 1,
            "NoseType3": 1, "LipType7": 1
        ])
    }

    @Test
    func shortInputAddsNothingAndDoesNotCrash() {
        #expect(ChargenMorphs.weights(morphs: [], parts: []).isEmpty)
        #expect(ChargenMorphs.sliders.count == 18)
    }

    @Test
    func positionsAddScaledWeightedDeltas() {
        let tri = TRIFile(
            baseVertices: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)],
            triangles: [],
            morphTargets: [
                TRIMorphTarget(
                    name: "NoseLong",
                    scale: 2,
                    deltas: [SIMD3(1, 0, 0), SIMD3(0, 1, 0)]
                ),
                TRIMorphTarget(name: "Bad", scale: 1, deltas: [SIMD3(9, 9, 9)])
            ]
        )
        let result = ChargenMorphs.positions(tri: tri, weights: ["NoseLong": 0.5, "Bad": 1])
        #expect(result == [SIMD3(1, 0, 0), SIMD3(1, 2, 1)])
    }

    @Test
    func weightBlendsThinAndHeavy() {
        let blended = ChargenMorphs.blend(
            thin: [SIMD3(0, 0, 0)],
            heavy: [SIMD3(2, 4, 6)],
            weight: 50
        )
        #expect(blended == [SIMD3(1, 2, 3)])
        #expect(ChargenMorphs.blend(thin: [], heavy: [SIMD3(1, 1, 1)], weight: 0) == nil)
    }

    @Test
    func tintsPaintByMaskStrengthAndSkipBadMasks() {
        let base: [UInt8] = [0, 0, 0, 255, 100, 100, 100, 255]
        let layers = [
            ChargenTintLayer(mask: [255, 0], color: SIMD4(200, 100, 50, 0), strength: 0.5),
            ChargenTintLayer(mask: [255], color: SIMD4(255, 255, 255, 255), strength: 1)
        ]
        let painted = ChargenTints.paint(rgba: base, layers: layers)
        #expect(painted == [100, 50, 25, 255, 100, 100, 100, 255])
    }

    @Test func coverageTakesTheRedChannelAndScalesByNearestTexel() {
        let mask: [UInt8] = [10, 0, 0, 255, 200, 0, 0, 255]
        #expect(ChargenTints.coverage(rgba: mask, width: 2, height: 1, toWidth: 4, toHeight: 2)
            == [10, 10, 200, 200, 10, 10, 200, 200])
        #expect(ChargenTints.coverage(rgba: [], width: 2, height: 1, toWidth: 2, toHeight: 1) == [
            0,
            0
        ])
    }
}
