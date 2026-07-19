// Synthetic skin block + bind-pose flatten tests. Layouts follow NifTools
// nif.xml; fixtures contain no game bytes (AGENTS.md legal boundary).

import Foundation
@testable import opensky
import simd
import Testing

struct NIFSkinTests {
    private static let attributes: UInt16 = 0x43 // vertex|uvs|skinned
    private static let positions = [
        SIMD3<Float>(0, 0, 0), SIMD3<Float>(100, 0, 0), SIMD3<Float>(0, 100, 0)
    ]

    private func fixture() throws -> NIFFile {
        let records = Self.positions.map { NIFFixture.skinnedVertex(position: $0) }
        let blocks: [NIFFixture.Block] = [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                translation: SIMD3(10, 0, 0)
            ))),
            .init("BSTriShape", NIFFixture.bsTriShape(
                skinRef: 3,
                attributes: Self.attributes,
                strideDwords: 8
            )),
            .init("BSDismemberSkinInstance", NIFFixture.skinInstance(
                dataRef: 4,
                partitionRef: 5,
                skeletonRootRef: 0,
                boneRefs: [1],
                bodyPartitions: [(flags: 257, bodyPart: 32)]
            )),
            .init("NiSkinData", NIFFixture.skinData(
                boneTransforms: [NIFFixture.niTransform(
                    translation: SIMD3(-10, 0, 0)
                )],
                vertexWeights: [[
                    (vertex: 0, weight: 1),
                    (vertex: 1, weight: 1),
                    (vertex: 2, weight: 1)
                ]]
            )),
            .init("NiSkinPartition", NIFFixture.skinPartition(
                vertexRecords: records,
                triangles: [0, 1, 2],
                bonePalette: [0],
                weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
                boneIndices: Array(repeating: .zero, count: 3)
            ))
        ]
        return try NIFFile(data: NIFFixture.file(blocks: blocks))
    }

    @Test func decodesInstanceDataAndPartition() throws {
        let file = try fixture()
        let instance = try NIFSkinInstance(data: file.blocks[3].data, isDismember: true)
        #expect(instance.dataRef == 4)
        #expect(instance.skinPartitionRef == 5)
        #expect(instance.skeletonRootRef == 0)
        #expect(instance.boneRefs == [1])
        #expect(instance.bodyPartitions == [.init(flags: 257, bodyPart: 32)])

        let data = try NIFSkinData(data: file.blocks[4].data)
        #expect(data.bones.count == 1)
        #expect(data.bones[0].vertexWeights.count == 3)
        #expect(data.bones[0].skinToBone.translation == SIMD3(-10, 0, 0))

        let partition = try NIFSkinPartition(
            data: file.blocks[5].data,
            header: file.header
        )
        #expect(partition.attributes == [.vertex, .uvs, .skinned])
        #expect(partition.vertices.positions == Self.positions)
        #expect(partition.vertices.boneWeights.count == 3)
        #expect(partition.partitions.count == 1)
        #expect(partition.partitions[0].vertexMap == [0, 1, 2])
        #expect(partition.partitions[0].triangleIndices == [0, 1, 2])
    }

    @Test func decodesSkeletonBoneTreeByName() throws {
        let blocks: [NIFFixture.Block] = [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(
                    nameIndex: 0,
                    translation: SIMD3(10, 0, 0)
                ),
                children: [1]
            )),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                nameIndex: 1,
                translation: SIMD3(0, 20, 0)
            )))
        ]
        let file = try NIFFile(data: NIFFixture.file(
            blocks: blocks,
            strings: ["Root", "Bone"]
        ))
        let skeleton = try NIFSkeleton(file: file)
        let bone = try #require(skeleton.boneTransforms["Bone"])

        #expect(bone.columns.3 == SIMD4(10, 20, 0, 1))
    }

    @Test func flattensBindPoseSkinningWithoutDistortion() throws {
        let model = try fixture().model()
        let mesh = try #require(model.meshes.first)
        let skinning = try #require(mesh.skinning)

        #expect(model.meshes.count == 1)
        #expect(model.skippedShapeCount == 0)
        #expect(mesh.positions == Self.positions)
        #expect(mesh.indices == [0, 1, 2])
        #expect(skinning.weights == Array(repeating: SIMD4(1, 0, 0, 0), count: 3))
        #expect(skinning.boneIndices == Array(repeating: .zero, count: 3))
        #expect(skinning.bindPoseMatrices.count == 1)
        let matrix = skinning.bindPoseMatrices[0]
        for column in 0 ..< 4 {
            #expect(simd_distance(matrix[column], matrix_identity_float4x4[column]) < 1e-5)
        }
        #expect(ModelBounds.containing(model: model) == ModelBounds(
            min: SIMD3(0, 0, 0),
            max: SIMD3(100, 100, 0)
        ))
    }

    @Test func rejectsPaletteIndexOutsideBoneList() throws {
        let file = try fixture()
        let badRecord = NIFFixture.skinnedVertex(
            position: .zero,
            boneIndices: SIMD4(1, 0, 0, 0)
        )
        let badPartition = NIFFixture.skinPartition(
            vertexRecords: [badRecord],
            triangles: [0, 0, 0],
            bonePalette: [0],
            weights: [SIMD4(1, 0, 0, 0)],
            boneIndices: [.zero]
        )
        var blocks = file.blocks.enumerated().map { index, block in
            NIFFixture.Block(block.typeName, index == 5 ? badPartition : block.data)
        }
        // Shape still points at the same valid block graph; partition now has
        // one vertex whose top stream selects nonexistent palette index 1.
        blocks[2] = .init("BSTriShape", NIFFixture.bsTriShape(
            skinRef: 3,
            attributes: Self.attributes,
            strideDwords: 8
        ))
        let malformed = try NIFFile(data: NIFFixture.file(blocks: blocks))
        #expect(throws: NIFError.self) { try malformed.model() }
    }
}
