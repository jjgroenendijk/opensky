// The interleaved vertex stream: smooth normals for a shape that stores none.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct InterleavedVertexLayoutTests {
    /// Two triangles folded along the x axis: one faces up, one faces +y.
    private static let fold = Mesh(
        name: nil, transform: matrix_identity_float4x4,
        positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)],
        normals: [], tangents: [], bitangents: [], uvs: [], colors: [],
        indices: [0, 1, 2, 0, 3, 1], materialSlot: 0
    )

    @Test func aMeshWithoutNormalsGetsAreaWeightedSmoothNormals() {
        let normals = InterleavedVertexLayout.smoothNormals(of: Self.fold)
        #expect(normals[2] == SIMD3(0, 0, 1))
        #expect(normals[3] == SIMD3(0, 1, 0))
        let shared = SIMD3<Float>(0, 1, 1) / sqrt(2)
        #expect(simd_distance(normals[0], shared) < 1e-5)
        #expect(simd_distance(normals[1], shared) < 1e-5)
    }

    @Test func theStreamCarriesTheBuiltNormals() {
        let floats = InterleavedVertexLayout.interleave(Self.fold)
        let normalStart = InterleavedVertexLayout.normalOffset / 4
        let stride = InterleavedVertexLayout.stride / 4
        let third = Array(floats[2 * stride + normalStart ..< 2 * stride + normalStart + 3])
        #expect(third == [0, 0, 1])
    }

    @Test func aDegenerateVertexKeepsTheDefaultNormal() {
        let lone = Mesh(
            name: nil, transform: matrix_identity_float4x4, positions: [SIMD3(0, 0, 0)],
            normals: [], tangents: [], bitangents: [], uvs: [], colors: [], indices: [],
            materialSlot: 0
        )
        #expect(InterleavedVertexLayout
            .smoothNormals(of: lone) == [InterleavedVertexLayout.defaultNormal])
    }
}
