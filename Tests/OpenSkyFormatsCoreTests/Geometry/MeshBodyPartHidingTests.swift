// A cut hides the triangles of one side's dismember partitions.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct MeshBodyPartHidingTests {
    /// Three triangles: neck 230, head 130, ears 143, as a FaceGen head is partitioned.
    private func head(parts: [MeshBodyPart]?) -> Mesh {
        Mesh(
            name: "Head",
            transform: matrix_identity_float4x4,
            positions: Array(repeating: .zero, count: 9),
            normals: [], tangents: [], bitangents: [], uvs: [], colors: [],
            indices: Array(0 ..< 9),
            materialSlot: 0,
            skinning: parts.map {
                MeshSkinning(
                    weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 9),
                    boneIndices: Array(repeating: .zero, count: 9),
                    bindPoseMatrices: [matrix_identity_float4x4],
                    bodyParts: $0
                )
            }
        )
    }

    private let faceParts = [
        MeshBodyPart(bodyPart: 230, indices: 0 ..< 3),
        MeshBodyPart(bodyPart: 130, indices: 3 ..< 6),
        MeshBodyPart(bodyPart: 143, indices: 6 ..< 9)
    ]

    @Test func theBodyKeepsTheNeckAndTheHeadTheRest() throws {
        let model = Model(meshes: [head(parts: faceParts)], materials: [], skippedShapeCount: 0)
        let body = try #require(
            model.keeping(DismemberCut(side: .body, keepsUnpartitioned: false)).meshes.first
        )
        #expect(body.indices == [0, 1, 2])
        #expect(body.skinning?.bodyParts == [MeshBodyPart(bodyPart: 230, indices: 0 ..< 3)])
        let cut = try #require(
            model.keeping(DismemberCut(side: .head, keepsUnpartitioned: true)).meshes.first
        )
        #expect(cut.indices == [3, 4, 5, 6, 7, 8])
        #expect(cut.skinning?.bodyParts == [
            MeshBodyPart(bodyPart: 130, indices: 0 ..< 3),
            MeshBodyPart(bodyPart: 143, indices: 3 ..< 6)
        ])
    }

    @Test func aMeshWithoutPartitionsGoesWithItsOwnerOnly() {
        let model = Model(meshes: [head(parts: nil)], materials: [], skippedShapeCount: 0)
        #expect(model.keeping(DismemberCut(side: .head, keepsUnpartitioned: true)).meshes
            .count == 1)
        #expect(model.keeping(DismemberCut(side: .body, keepsUnpartitioned: false)).meshes.isEmpty)
    }

    @Test func aMeshLeftEmptyGoesAway() {
        let gore = [MeshBodyPart(bodyPart: 150, indices: 0 ..< 9)]
        #expect(head(parts: gore).hidingBodyParts(where: DismemberSide.body.hides) == nil)
        #expect(head(parts: gore).hidingBodyParts(where: DismemberSide.head.hides) != nil)
    }

    @Test func aRangePastTheIndicesIsClamped() throws {
        let mesh = head(parts: [MeshBodyPart(bodyPart: 32, indices: 6 ..< 99)])
        let kept = try #require(mesh.hidingBodyParts(where: { $0 == 30 }))
        #expect(kept.indices == mesh.indices, "nothing hidden, so the mesh comes back as is")
        let neck = head(parts: [
            MeshBodyPart(bodyPart: 30, indices: 0 ..< 3), MeshBodyPart(
                bodyPart: 32,
                indices: 6 ..< 99
            )
        ])
        #expect(neck.hidingBodyParts(where: { $0 == 30 })?.indices == [6, 7, 8])
    }
}
