// A shape's billboard node, moved into the shape's own frame for the vertex shader
// (docs/formats/nif-sequences.md#billboard-nodes).

import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct MeshBillboardTests {
    @Test func theNodeMovesIntoTheShapeFrame() throws {
        let node = MatrixMath.translation([5, 0, 0]) * MatrixMath.rotationZ(radians: .pi / 2)
        let shape = MatrixMath.translation([1, 0, 0]) * MatrixMath.scale(uniform: 2)
        let billboard = try #require(MeshBillboard(node: node, shape: shape, mode: 4))
        #expect(simd_length(billboard.pivot - [2, 0, 0]) < 1e-5)
        // The scale of the shape leaves the rotation a pure turn.
        #expect(simd_length(billboard.rotation.act([1, 0, 0]) - [0, 1, 0]) < 1e-5)
        #expect(billboard.mode == 4)
    }

    @Test func aShapeThatCannotBeInvertedHasNoBillboard() {
        #expect(MeshBillboard(
            node: matrix_identity_float4x4, shape: MatrixMath.scale(uniform: 0), mode: 4
        ) == nil)
    }
}
