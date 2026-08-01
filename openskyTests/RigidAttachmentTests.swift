// Rigid bone attachment maths (issue #178, roadmap item 12.2.1).
//
// The interesting property is not the palette's contents but what the GPU
// computes from them, so the tests reproduce the shader's composition —
// `world = modelMatrix * (bone * v)` with `modelMatrix = actor * meshLocal`
// (Shaders.metal `skinnedMeshVertex`, RenderScene instance assembly) — and
// assert on the world position a vertex lands at. That is what makes a sign or
// ordering error visible instead of a matrix that merely looks plausible.

import Foundation
@testable import opensky
import simd
import Testing

struct RigidAttachmentTests {
    /// A mesh with one vertex at `origin`, a local transform, and no skinning.
    private func mesh(
        vertex: SIMD3<Float>,
        transform: float4x4 = matrix_identity_float4x4
    ) -> Mesh {
        Mesh(
            name: "sword",
            transform: transform,
            positions: [vertex],
            normals: [SIMD3(0, 0, 1)],
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0, 0)],
            colors: [],
            indices: [0, 0, 0],
            materialSlot: 0
        )
    }

    private func model(_ meshes: [Mesh]) -> Model {
        Model(meshes: meshes, materials: [], skippedShapeCount: 0)
    }

    /// The shader's composition, so a test asserts on where the vertex ends up
    /// rather than on the palette entry in isolation.
    private func world(
        _ mesh: Mesh,
        bone: float4x4,
        actor: float4x4 = matrix_identity_float4x4
    ) -> SIMD3<Float> {
        let modelMatrix = actor * mesh.transform
        let skinned = bone * SIMD4(mesh.positions[0], 1)
        let out = modelMatrix * skinned
        return SIMD3(out.x, out.y, out.z)
    }

    @Test func everyVertexIsFullyWeightedToTheOneNamedBone() throws {
        let source = model([mesh(vertex: SIMD3(1, 2, 3))])
        let attached = RigidAttachment.skinned(
            source, to: "Weapon", restTransform: matrix_identity_float4x4
        )
        let skinning = try #require(attached.meshes[0].skinning)

        #expect(skinning.boneNames == ["Weapon"])
        #expect(skinning.weights == [SIMD4(1, 0, 0, 0)])
        #expect(skinning.boneIndices == [SIMD4(0, 0, 0, 0)])
        #expect(skinning.bindPoseMatrices.count == 1)
        #expect(skinning.skinToBoneMatrices.count == 1)
    }

    /// The whole point: with the animated pose in hand, the vertex lands where
    /// the bone carries it, in the actor's space.
    @Test func animatedPosePutsTheVertexAtTheBone() throws {
        let localOffset = SIMD3<Float>(0, 0, 10)
        let source = model([mesh(vertex: localOffset)])
        let attached = RigidAttachment.skinned(
            source, to: "Weapon", restTransform: matrix_identity_float4x4
        )
        let mesh = attached.meshes[0]
        let skinning = try #require(mesh.skinning)
        let handPosition = SIMD3<Float>(30, 100, -5)

        // What RenderMesh.updateSkinningPose composes for a matched bone.
        let palette = skinning.rootParentToSkin
            * MatrixMath.translation(handPosition)
            * skinning.skinToBoneMatrices[0]

        let result = world(mesh, bone: palette)

        #expect(simd_distance(result, handPosition + localOffset) < 1e-4)
    }

    /// A mesh-local transform must survive: the weapon's own geometry offset is
    /// applied first, then the bone, then the actor. Getting that order wrong
    /// is the failure this test exists for.
    @Test func meshLocalTransformIsAppliedUnderTheBoneNotOverIt() throws {
        let localTransform = MatrixMath.translation(SIMD3(0, 0, 4))
        let source = model([mesh(vertex: SIMD3(1, 0, 0), transform: localTransform)])
        let attached = RigidAttachment.skinned(
            source, to: "Weapon", restTransform: matrix_identity_float4x4
        )
        let mesh = attached.meshes[0]
        let skinning = try #require(mesh.skinning)
        let hand = MatrixMath.translation(SIMD3(0, 50, 0))
        let actor = MatrixMath.translation(SIMD3(1000, 0, 0))

        let palette = skinning.rootParentToSkin * hand * skinning.skinToBoneMatrices[0]
        let result = world(mesh, bone: palette, actor: actor)

        // actor · hand · meshLocal · vertex = (1000,0,0)+(0,50,0)+(0,0,4)+(1,0,0)
        #expect(simd_distance(result, SIMD3(1001, 50, 4)) < 1e-4)
    }

    /// Without an animated pose the mesh keeps its bind palette, which must put
    /// the model at the skeleton's rest transform for the node — not at the
    /// actor's origin.
    @Test func bindPaletteUsesTheSkeletonRestTransform() throws {
        let rest = MatrixMath.translation(SIMD3(0, 60, 12))
        let source = model([mesh(vertex: .zero)])
        let attached = RigidAttachment.skinned(source, to: "Weapon", restTransform: rest)
        let mesh = attached.meshes[0]
        let skinning = try #require(mesh.skinning)

        let result = world(mesh, bone: skinning.bindPoseMatrices[0])

        #expect(simd_distance(result, SIMD3(0, 60, 12)) < 1e-4)
    }

    /// Already-rigged geometry belongs to some other rig; overwriting its
    /// palette would corrupt it rather than attach it.
    @Test func alreadySkinnedMeshIsLeftAlone() {
        let skinned = Mesh(
            name: "rigged",
            transform: matrix_identity_float4x4,
            positions: [.zero],
            normals: [],
            tangents: [],
            bitangents: [],
            uvs: [],
            colors: [],
            indices: [0, 0, 0],
            materialSlot: 0,
            skinning: MeshSkinning(
                weights: [SIMD4(1, 0, 0, 0)],
                boneIndices: [SIMD4(0, 0, 0, 0)],
                bindPoseMatrices: [matrix_identity_float4x4],
                boneNames: ["NPC Spine [Spn0]"]
            )
        )
        let attached = RigidAttachment.skinned(
            model([skinned]), to: "Weapon", restTransform: matrix_identity_float4x4
        )

        #expect(attached.meshes[0].skinning?.boneNames == ["NPC Spine [Spn0]"])
    }

    @Test func materialsAndSkippedShapeCountSurvive() {
        let source = Model(meshes: [mesh(vertex: .zero)], materials: [], skippedShapeCount: 3)
        let attached = RigidAttachment.skinned(
            source, to: "Weapon", restTransform: matrix_identity_float4x4
        )

        #expect(attached.skippedShapeCount == 3)
        #expect(attached.meshes.count == 1)
    }
}

struct NIFSkeletonBoneLookupTests {
    /// The Havok rig spells the drawn-weapon node `Weapon` and the NIF spells
    /// it `WEAPON`, so the bind-transform lookup folds case. Observed with
    /// `openskycli skeleton --nif` against the vanilla character skeleton.
    @Test func boneLookupFallsBackToACaseInsensitiveMatch() throws {
        let skeleton = NIFSkeleton(boneTransforms: [
            "WEAPON": MatrixMath.translation(SIMD3(1, 2, 3)),
            "NPC R Hand [RHnd]": matrix_identity_float4x4
        ])

        let folded = try #require(skeleton.transform(forBoneNamed: "Weapon"))
        #expect(folded.columns.3 == SIMD4(1, 2, 3, 1))
        // An exact match still resolves, and an unknown name stays nil.
        #expect(skeleton.transform(forBoneNamed: "NPC R Hand [RHnd]") != nil)
        #expect(skeleton.transform(forBoneNamed: "Quiver") == nil)
    }
}
