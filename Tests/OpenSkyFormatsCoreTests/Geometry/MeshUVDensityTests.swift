// The UV density of a mesh: how many texture repeats one world unit holds.

import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct MeshUVDensityTests {
    /// A 64 x 64 quad in two triangles.
    private let positions: [SIMD3<Float>] = [[0, 0, 0], [64, 0, 0], [64, 64, 0], [0, 64, 0]]
    private let indices: [UInt16] = [0, 1, 2, 0, 2, 3]

    @Test func aQuadWithTheWholeTextureHoldsOneRepeat() {
        let uvs: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
        let density = MeshUVDensity.uvPerUnit(positions: positions, uvs: uvs, indices: indices)
        #expect(abs(density - 1.0 / 64) < 1e-6)
    }

    @Test func tilingRaisesTheDensity() {
        let uvs: [SIMD2<Float>] = [[0, 0], [4, 0], [4, 4], [0, 4]]
        let density = MeshUVDensity.uvPerUnit(positions: positions, uvs: uvs, indices: indices)
        #expect(abs(density - 4.0 / 64) < 1e-6)
    }

    @Test func missingUVsOrAreaGiveZero() {
        #expect(MeshUVDensity.uvPerUnit(positions: positions, uvs: [], indices: indices) == 0)
        let flat: [SIMD3<Float>] = Array(repeating: [1, 1, 1], count: 4)
        let uvs: [SIMD2<Float>] = [[0, 0], [1, 0], [1, 1], [0, 1]]
        #expect(MeshUVDensity.uvPerUnit(positions: flat, uvs: uvs, indices: indices) == 0)
    }
}
