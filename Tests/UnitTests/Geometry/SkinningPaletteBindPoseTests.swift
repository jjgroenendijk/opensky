// The bind-pose round trip the actor animation path rests on (issue #354):
// composing a Havok rig's own reference pose and writing it into a NIF skin
// must reproduce that skin's bind palette, so a body that is animated but not
// yet moving stands exactly where the un-animated body stands.
//
// Both halves are synthetic and built in code — a NIF assembled byte by byte
// through `NIFFixture` and a rig assembled from the values a Havok packfile
// carries — so this is a deterministic test of the two formats' conventions
// meeting, with no game file anywhere near it (AGENTS.md "Legal & IP").
//
// The conventions are what the test is really about. Havok multiplies column
// vectors and NIF multiplies row vectors, so the two files spell the same bone
// rotation as transposes of each other, and the NIF side has to be transposed
// on the way in. Skipping that transpose is what tore skinned actors apart:
// the bind palette still came out as the identity, because the NIF's own two
// halves cancel either way, but every pose written over it was composed in the
// wrong convention.

import Foundation
@testable import opensky
import simd
import Testing

struct SkinningPaletteBindPoseTests {
    /// One bone of the synthetic rig, in its parent's space.
    private struct Bone {
        let name: String
        let parent: Int
        let translation: SIMD3<Float>
        let rotation: simd_quatf

        var localMatrix: float4x4 {
            MatrixMath.translation(translation) * float4x4(rotation)
        }
    }

    /// Deliberately awkward rotations: three different axes, none of them a
    /// half turn, so a transposed rotation cannot pass by accident.
    private static let bones = [
        Bone(
            name: "Hip",
            parent: -1,
            translation: SIMD3(0, 0, 70),
            rotation: simd_quatf(angle: 0.37, axis: SIMD3(0, 0, 1))
        ),
        Bone(
            name: "Thigh",
            parent: 0,
            translation: SIMD3(-6.5, 0, 0),
            rotation: simd_quatf(angle: 2.1, axis: normalize(SIMD3(0.2, 1, 0.3)))
        ),
        Bone(
            name: "Calf",
            parent: 1,
            translation: SIMD3(0, 0, -35),
            rotation: simd_quatf(angle: -0.8, axis: normalize(SIMD3(1, 0.4, 0)))
        )
    ]

    /// Skin space sits away from the skeleton root's parent, as it does in a
    /// vanilla body NIF, so a palette that dropped `rootParentToSkin` fails.
    private static let rootParentToSkin = MatrixMath.translation(SIMD3(0.5, -1.5, -120))

    private static var bindWorlds: [float4x4] {
        var worlds: [float4x4] = []
        for bone in bones {
            let parent = bone.parent < 0 ? matrix_identity_float4x4 : worlds[bone.parent]
            worlds.append(parent * bone.localMatrix)
        }
        return worlds
    }

    /// The rig as a packfile hands it over: the same bones, same convention.
    private static var rig: HKASkeleton {
        HKASkeleton(
            name: "synthetic",
            bones: bones.map { HKABone(name: $0.name, lockTranslation: false) },
            parentIndices: bones.map(\.parent),
            referencePose: bones.map { bone in
                HKABonePose(
                    translation: bone.translation,
                    rotation: bone.rotation,
                    scale: SIMD3(repeating: 1)
                )
            }
        )
    }

    @Test func composedReferencePoseReproducesTheBindPalette() throws {
        let skinning = try #require(Self.skinnedModel().meshes.first?.skinning)
        let palette = try #require(SkinningPalette(skinning))
        // The decoded bind palette is the reference: whatever the NIF says the
        // mesh looks like standing still.
        #expect(palette.bindPoseMatrices.count == Self.bones.count)

        let posed = try palette.posed(by: Self.referencePoseWorlds())

        #expect(posed.matchedBoneCount == Self.bones.count)
        for (index, matrix) in posed.matrices.enumerated() {
            let bind = palette.bindPoseMatrices[index]
            #expect(
                Self.maxDelta(matrix, bind) < 1e-4,
                "bone \(Self.bones[index].name) moved off its bind palette: \(matrix)"
            )
        }
    }

    /// The bind pose the NIF's own inverse-bind transforms describe is the one
    /// the rig composes — not merely a palette that cancels. Without this, a
    /// skin whose two halves were both wrong the same way would still pass.
    @Test func nifInverseBindMatchesTheRigsComposedWorldPose() throws {
        let skinning = try #require(Self.skinnedModel().meshes.first?.skinning)
        let worlds = Self.bindWorlds

        for (index, skinToBone) in skinning.skinToBoneMatrices.enumerated() {
            let implied = skinning.rootParentToSkin.inverse * skinToBone.inverse
            #expect(
                Self.maxDelta(implied, worlds[index]) < 1e-4,
                "bone \(Self.bones[index].name) binds somewhere the rig never puts it"
            )
        }
    }

    /// A NIF rotation read without the transpose turns every rotated bone the
    /// wrong way, so the palette stops being the bind palette. This is the
    /// shape of the defect the two tests above close.
    @Test func readingNIFRotationsUntransposedMovesTheMesh() throws {
        let skinning = try #require(Self.skinnedModel().meshes.first?.skinning)
        let untransposed = MeshSkinning(
            weights: skinning.weights,
            boneIndices: skinning.boneIndices,
            bindPoseMatrices: skinning.bindPoseMatrices,
            boneNames: skinning.boneNames,
            rootParentToSkin: skinning.rootParentToSkin,
            skinToBoneMatrices: skinning.skinToBoneMatrices.map(Self.transposingRotation)
        )
        let palette = try #require(SkinningPalette(untransposed))
        let posed = try palette.posed(by: Self.referencePoseWorlds())
        let deltas = zip(posed.matrices, palette.bindPoseMatrices).map(Self.maxDelta)

        #expect(
            deltas.allSatisfy { $0 > 1e-3 },
            "an unrotated rig proves nothing — every bone must move: \(deltas)"
        )
        #expect(
            (deltas.max() ?? 0) > 1,
            "the worst bone should be displaced by world units, not by rounding"
        )
    }

    // MARK: - Rig

    /// The rig's own reference pose, composed through its parent chain and
    /// keyed by bone name — exactly what `PlayerAnimationPlayback` writes.
    private static func referencePoseWorlds() throws -> [String: float4x4] {
        let world = try SkeletonPoseMath.worldMatrices(
            skeleton: rig, localPoses: rig.referencePose
        )
        var named: [String: float4x4] = [:]
        for (name, transform) in zip(rig.boneNames, world) {
            named[name] = transform
        }
        return named
    }

    // MARK: - Fixture

    /// A skinned NIF over the same bind pose: one node per bone in a chain,
    /// one three-vertex shape, and a `NiSkinData` whose bone transforms are the
    /// exact inverse bind, so the decoded bind palette is the identity.
    private static func skinnedModel() throws -> Model {
        let positions = [
            SIMD3<Float>(0, 0, 0), SIMD3<Float>(4, 0, -2), SIMD3<Float>(-4, 1, -6)
        ]
        var blocks: [NIFFixture.Block] = [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1, 4]
            ))
        ]
        for (index, bone) in bones.enumerated() {
            blocks.append(.init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(
                    nameIndex: UInt32(index + 1),
                    translation: bone.translation,
                    rotationRows: rows(of: simd_float3x3(bone.rotation))
                ),
                children: index + 1 < bones.count ? [Int32(index + 2)] : []
            )))
        }
        blocks.append(.init("BSTriShape", NIFFixture.bsTriShape(
            skinRef: 5, attributes: 0x43, strideDwords: 8
        )))
        blocks.append(.init("BSDismemberSkinInstance", NIFFixture.skinInstance(
            dataRef: 6,
            partitionRef: 7,
            skeletonRootRef: 0,
            boneRefs: (0 ..< bones.count).map { Int32($0 + 1) },
            bodyPartitions: [(flags: 257, bodyPart: 32)]
        )))
        blocks.append(.init("NiSkinData", NIFFixture.skinData(
            rootParentToSkin: NIFFixture.niTransform(
                translation: translation(of: rootParentToSkin)
            ),
            boneTransforms: bindWorlds.map(skinToBoneTransform(bindWorld:)),
            vertexWeights: [
                [(vertex: 0, weight: 1)],
                [(vertex: 1, weight: 1)],
                [(vertex: 2, weight: 1)]
            ]
        )))
        blocks.append(.init("NiSkinPartition", NIFFixture.skinPartition(
            vertexRecords: positions.map { NIFFixture.skinnedVertex(position: $0) },
            triangles: [0, 1, 2],
            bonePalette: [0, 1, 2],
            weights: Array(repeating: SIMD4(1, 0, 0, 0), count: 3),
            boneIndices: [SIMD4(0, 0, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(2, 0, 0, 0)]
        )))
        let file = try NIFFile(data: NIFFixture.file(
            blocks: blocks, strings: ["Root"] + bones.map(\.name)
        ))
        return try file.model()
    }

    /// The inverse bind for one bone: what the NIF stores so that
    /// `rootParentToSkin * bindWorld * skinToBone` is the identity.
    private static func skinToBoneTransform(bindWorld: float4x4) -> Data {
        let matrix = bindWorld.inverse * rootParentToSkin.inverse
        return NIFFixture.niTransform(
            translation: translation(of: matrix),
            rotationRows: rows(of: simd_float3x3(
                SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
            ))
        )
    }

    // MARK: - Matrices

    /// The nine floats a NIF stores for `rotation`: its rows, because the
    /// format multiplies row vectors.
    private static func rows(of rotation: simd_float3x3) -> [Float] {
        let transposed = rotation.transpose
        return (0 ..< 3).flatMap { column -> [Float] in
            let values = transposed[column]
            return [values.x, values.y, values.z]
        }
    }

    private static func translation(of matrix: float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    /// One transform with its rotation transposed and its translation left
    /// alone — what dropping the NIF transpose produces.
    private static func transposingRotation(_ matrix: float4x4) -> float4x4 {
        var result = matrix
        for column in 0 ..< 3 {
            result[column] = SIMD4(
                matrix[0][column], matrix[1][column], matrix[2][column], 0
            )
        }
        return result
    }

    private static func maxDelta(_ lhs: float4x4, _ rhs: float4x4) -> Float {
        var worst: Float = 0
        for column in 0 ..< 4 {
            let difference = lhs[column] - rhs[column]
            for row in 0 ..< 4 {
                worst = max(worst, abs(difference[row]))
            }
        }
        return worst
    }
}
