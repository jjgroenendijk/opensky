// A tree's wind values reach the shader as one float4 (docs/rendering/trees.md).

import OpenSkyRendering
import Testing

struct TreeMotionTests {
    private let pine = TreeMotion(
        sway: 0.15,
        swayFrequency: 2,
        leafAmplitude: 4.5,
        leafFrequency: 1.75
    )

    @Test func aWindWeightedShapeGetsLeafValues() {
        #expect(TreeMotion.uniform(pine, windWeighted: true) == SIMD4(0.15, 2, 4.5, 1.75))
    }

    @Test func aShapeWithoutWeightsOnlySways() {
        #expect(TreeMotion.uniform(pine, windWeighted: false) == SIMD4(0.15, 2, 0, 0))
    }

    @Test func leavesWithoutATreeRecordUseTheDefaults() {
        #expect(TreeMotion.uniform(nil, windWeighted: true) == SIMD4(
            0, 0, TreeMotion.defaultLeafAmplitude, TreeMotion.defaultLeafFrequency
        ))
        #expect(TreeMotion.uniform(nil, windWeighted: false) == .zero)
    }
}
