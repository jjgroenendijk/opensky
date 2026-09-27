// SSE skin influence index-space tests: the top-level BSVertexDataSSE stream
// stores skin-instance-global bone indices, while the per-partition Bone
// Indices array is palette-local. Fixtures follow NifTools nif.xml; no game
// bytes (AGENTS.md legal boundary). Observed values probed on SabreCat.nif,
// documented in docs/formats/nif.md.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFSkinIndexSpaceTests {
    private static let attributes: UInt16 = 0x43 // vertex|uvs|skinned
    private static let positions = [
        SIMD3<Float>(0, 0, 0), SIMD3<Float>(100, 0, 0), SIMD3<Float>(0, 100, 0)
    ]

    @Test func rejectsPaletteIndexOutsideBoneList() throws {
        // Partition-local path (empty top-level stream): the per-partition
        // Bone Indices array is palette-local, so index 1 into a 1-entry
        // palette must still fail safely.
        let records = Self.positions.map { NIFFixture.skinnedVertex(position: $0) }
        let inherited = NIFFixture.bsTriShape(
            skinRef: 3,
            attributes: Self.attributes,
            strideDwords: 8,
            vertexCountOverride: Self.positions.count
        )
        let blocks: [NIFFixture.Block] = [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("NiNode", NIFFixture.niNode()),
            .init("BSDynamicTriShape", NIFFixture.bsDynamicTriShape(
                inherited: inherited,
                positions: Self.positions
            )),
            .init("NiSkinInstance", NIFFixture.skinInstance(
                dataRef: 4,
                partitionRef: 5,
                skeletonRootRef: 0,
                boneRefs: [1]
            )),
            .init("NiSkinData", NIFFixture.skinData(
                boneTransforms: [NIFFixture.niTransform()],
                vertexWeights: [[]]
            )),
            .init("NiSkinPartition", NIFFixture.skinPartition(
                vertexRecords: records,
                topLevelVertexRecords: [],
                triangles: [0, 1, 2],
                bonePalette: [0],
                weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
                boneIndices: [SIMD4(1, 0, 0, 0), .zero, .zero]
            ))
        ]
        let malformed = try NIFFile(data: NIFFixture.file(blocks: blocks))
        #expect(throws: NIFError.self) { try malformed.model() }
    }

    @Test func flattensGlobalIndexVariantWithNonIdentityPalette() throws {
        // SabreCat variant: top-level stream carries global bone indices while
        // the partition palette is non-identity and smaller than the highest
        // global index. Remapping globals through the palette (the old bug)
        // would throw; treating them as global flattens cleanly.
        let global = [SIMD4<UInt8>(0, 0, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(2, 0, 0, 0)]
        let records = zip(Self.positions, global).map {
            NIFFixture.skinnedVertex(position: $0, boneIndices: $1)
        }
        let model = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2, 3, 4])),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                translation: SIMD3(10, 0, 0)
            ))),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                translation: SIMD3(0, 10, 0)
            ))),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                translation: SIMD3(0, 0, 10)
            ))),
            .init("BSTriShape", NIFFixture.bsTriShape(
                skinRef: 5,
                attributes: Self.attributes,
                strideDwords: 8
            )),
            .init("NiSkinInstance", NIFFixture.skinInstance(
                dataRef: 6,
                partitionRef: 7,
                skeletonRootRef: 0,
                boneRefs: [1, 2, 3]
            )),
            .init("NiSkinData", NIFFixture.skinData(
                boneTransforms: Array(repeating: NIFFixture.niTransform(), count: 3),
                vertexWeights: [[], [], []]
            )),
            .init("NiSkinPartition", NIFFixture.skinPartition(
                vertexRecords: records,
                triangles: [0, 1, 2],
                bonePalette: [1, 0], // non-identity, smaller than max global 2
                weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
                boneIndices: Array(repeating: .zero, count: 3),
                globalVertexBuffer: true
            ))
        ])).model()
        let mesh = try #require(model.meshes.first)
        let skinning = try #require(mesh.skinning)

        #expect(model.meshes.count == 1)
        #expect(skinning.boneIndices == [
            SIMD4(0, 0, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(2, 0, 0, 0)
        ])
        #expect(skinning.weights == Array(repeating: SIMD4(1, 0, 0, 0), count: 3))
        #expect(skinning.bindPoseMatrices.count == 3)
    }

    /// Vanilla first-person armour (issue #190) carries vertices whose
    /// top-level influence lanes are all zero while the partition-local ones
    /// for the same vertex are populated. Reading the empty global lanes gave
    /// a zero-total vertex and threw the whole file away, so an empty global
    /// entry defers to the partition when the partition has influences.
    @Test func fallsBackToPartitionInfluencesWhenTheGlobalEntryIsEmpty() throws {
        let globalWeights: [SIMD4<Float>] = [
            SIMD4(1, 0, 0, 0), .zero, SIMD4(1, 0, 0, 0)
        ]
        let globalIndices: [SIMD4<UInt8>] = [
            SIMD4(0, 0, 0, 0), SIMD4(0, 0, 0, 0), SIMD4(2, 0, 0, 0)
        ]
        let records = zip(Self.positions, zip(globalWeights, globalIndices)).map {
            NIFFixture.skinnedVertex(position: $0, weights: $1.0, boneIndices: $1.1)
        }
        let model = try Self.skinnedModel(
            records: records,
            // Palette entry 0 is bone 1, so a vertex resolved locally lands on
            // a different bone than the same index read as a global would.
            bonePalette: [1, 0, 2],
            weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
            boneIndices: Array(repeating: .zero, count: 3)
        )
        let skinning = try #require(model.meshes.first?.skinning)

        // Vertex 1 is the one that fell back: every one of its palette-local
        // lanes is index 0, which the palette maps to bone 1. Vertices 0 and 2
        // kept the global lanes they already had.
        #expect(skinning.boneIndices == [
            SIMD4(0, 0, 0, 0), SIMD4(1, 1, 1, 1), SIMD4(2, 0, 0, 0)
        ])
        #expect(skinning.weights == Array(repeating: SIMD4(1, 0, 0, 0), count: 3))
    }

    /// A vertex with no influence in either space keeps its zero weights. It
    /// collapses onto the skeleton root, which is what the hardware would do
    /// with it anyway, and is a better answer than refusing a mesh whose other
    /// hundreds of vertices are fine.
    @Test func keepsZeroWeightsWhenNeitherSpaceHasInfluences() throws {
        let records = Self.positions.map {
            NIFFixture.skinnedVertex(position: $0, weights: .zero)
        }
        let model = try Self.skinnedModel(
            records: records,
            bonePalette: [0, 1, 2],
            weights: Array(repeating: .zero, count: 3),
            boneIndices: Array(repeating: .zero, count: 3)
        )
        let skinning = try #require(model.meshes.first?.skinning)
        #expect(skinning.weights == Array(repeating: SIMD4<Float>.zero, count: 3))
    }

    @Test func stillRefusesANonFiniteTotalWeight() throws {
        let records = Self.positions.map {
            NIFFixture.skinnedVertex(position: $0, weights: SIMD4(.infinity, 0, 0, 0))
        }
        #expect(throws: NIFError.self) {
            try Self.skinnedModel(
                records: records,
                bonePalette: [0, 1, 2],
                weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
                boneIndices: Array(repeating: .zero, count: 3)
            )
        }
    }

    /// One skinned `BSTriShape` over three bones, its influences supplied in
    /// both index spaces so a test can state which one it expects to win.
    private static func skinnedModel(
        records: [Data],
        bonePalette: [UInt16],
        weights: [SIMD4<Float>],
        boneIndices: [SIMD4<UInt8>]
    ) throws -> Model {
        try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2, 3, 4])),
            .init("NiNode", NIFFixture.niNode()),
            .init("NiNode", NIFFixture.niNode()),
            .init("NiNode", NIFFixture.niNode()),
            .init("BSTriShape", NIFFixture.bsTriShape(
                skinRef: 5, attributes: attributes, strideDwords: 8
            )),
            .init("NiSkinInstance", NIFFixture.skinInstance(
                dataRef: 6, partitionRef: 7, skeletonRootRef: 0, boneRefs: [1, 2, 3]
            )),
            .init("NiSkinData", NIFFixture.skinData(
                boneTransforms: Array(repeating: NIFFixture.niTransform(), count: 3),
                vertexWeights: [[], [], []]
            )),
            .init("NiSkinPartition", NIFFixture.skinPartition(
                vertexRecords: records,
                triangles: [0, 1, 2],
                bonePalette: bonePalette,
                weights: weights,
                boneIndices: boneIndices,
                globalVertexBuffer: true
            ))
        ])).model()
    }

    @Test func retainsGlobalVertexBufferFlag() throws {
        let records = Self.positions.map { NIFFixture.skinnedVertex(position: $0) }
        let data = NIFFixture.skinPartition(
            vertexRecords: records,
            triangles: [0, 1, 2],
            bonePalette: [0],
            weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
            boneIndices: Array(repeating: .zero, count: 3),
            globalVertexBuffer: true
        )
        let header = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode())
        ])).header
        let partition = try NIFSkinPartition(data: data, header: header)
        #expect(partition.partitions[0].usesGlobalVertexBuffer)
    }
}
