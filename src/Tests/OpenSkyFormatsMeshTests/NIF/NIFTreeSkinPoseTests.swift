// A tree's skin drawn in its bones' pose. Rule: docs/formats/nif-skinning.md.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFTreeSkinPoseTests {
    private static let positions = [
        SIMD3<Float>(0, 0, 0), SIMD3<Float>(100, 0, 0), SIMD3<Float>(0, 100, 0)
    ]

    /// The bone node stands at x = 10, while the bind data puts it at x = 30.
    private func model(rootType: String) throws -> Model {
        var root = NIFFixture.niNode(children: [1, 2])
        if rootType == "BSTreeNode" {
            root.append(Data(count: 8))
        }
        let blocks: [NIFFixture.Block] = [
            .init(rootType, root),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                translation: SIMD3(10, 0, 0)
            ))),
            .init("BSTriShape", NIFFixture.bsTriShape(
                skinRef: 3, shaderPropertyRef: 6, attributes: 0x43, strideDwords: 8
            )),
            .init("NiSkinInstance", NIFFixture.skinInstance(
                dataRef: 4, partitionRef: 5, skeletonRootRef: 0, boneRefs: [1]
            )),
            .init("NiSkinData", NIFFixture.skinData(
                boneTransforms: [NIFFixture.niTransform(translation: SIMD3(-30, 0, 0))],
                vertexWeights: [[]]
            )),
            .init("NiSkinPartition", NIFFixture.skinPartition(
                vertexRecords: Self.positions.map { NIFFixture.skinnedVertex(position: $0) },
                triangles: [0, 1, 2],
                bonePalette: [0],
                skin: (
                    Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
                    Array(repeating: .zero, count: 3)
                )
            )),
            .init("BSLightingShaderProperty", NIFFixture.bsLightingShaderProperty())
        ]
        return try NIFFile(data: NIFFixture.file(blocks: blocks)).model()
    }

    @Test func treeDrawsItsBonePoseOverItsBindData() throws {
        let mesh = try #require(try model(rootType: "BSTreeNode").meshes.first)
        let skinning = try #require(mesh.skinning)

        #expect(mesh.positions == Self.positions.map { $0 - SIMD3(20, 0, 0) })
        #expect(simd_distance(skinning.bindPoseMatrices[0].columns.3, SIMD4(0, 0, 0, 1)) < 1e-5)
    }

    @Test func otherRootKeepsTheStoredPositions() throws {
        let mesh = try #require(try model(rootType: "NiNode").meshes.first)

        #expect(mesh.positions == Self.positions)
    }
}
