// The `_0`/`_1` body pair blends vertex for vertex by actor weight.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct BodyWeightBlendTests {
    private func model(x: Float, vertexCount: Int = 3) -> Model {
        Model(
            meshes: [Mesh(
                name: "Body",
                transform: matrix_identity_float4x4,
                positions: Array(repeating: SIMD3(x, 0, 0), count: vertexCount),
                normals: Array(repeating: SIMD3(0, 0, 1), count: vertexCount),
                tangents: [],
                bitangents: [],
                uvs: [],
                colors: [],
                indices: [0, 1, 2],
                materialSlot: 0
            )],
            materials: [],
            skippedShapeCount: 0
        )
    }

    @Test func thinPathSwapsTheHeavySuffix() {
        #expect(BodyWeightBlend.thinPath(forHeavy: "armor\\iron\\cuirass_1.nif")
            == "armor\\iron\\cuirass_0.nif")
        #expect(BodyWeightBlend.thinPath(forHeavy: "Body_1.NIF") == "Body_0.nif")
        #expect(BodyWeightBlend.thinPath(forHeavy: "helmet.nif") == nil)
    }

    @Test func weightMovesVerticesFromThinToHeavy() {
        let blended = BodyWeightBlend.blend(thin: model(x: 0), heavy: model(x: 10), weight: 0.25)
        #expect(blended.meshes.first?.positions.first == SIMD3(2.5, 0, 0))
        #expect(blended.meshes.first?.normals.first == SIMD3(0, 0, 1))
    }

    @Test func aShapeThatDoesNotPairKeepsTheHeavyVertices() {
        let blended = BodyWeightBlend.blend(
            thin: model(x: 0, vertexCount: 4), heavy: model(x: 10), weight: 0
        )
        #expect(blended.meshes.first?.positions.first == SIMD3(10, 0, 0))
    }
}
