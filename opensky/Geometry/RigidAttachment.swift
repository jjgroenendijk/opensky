// Rigid bone attachment (issue #178, roadmap item 12.2.1): rewrite a static
// model so that it rides one named skeleton bone.
//
// The problem this solves is that a `RenderScene` bakes every placement's
// transform into its draw instances when the scene is built, and cell scenes
// are built on the streaming queue rather than per frame. A drawn weapon has
// to follow the hand *every* frame, so it cannot be a placement whose
// transform is fixed at build time. The one per-frame transform channel that
// already exists is GPU skinning: `ActorAnimationPlayback` pushes a named-bone
// pose into every skinned mesh of an actor once per frame.
//
// So a weapon becomes a skinned mesh with exactly one bone. Every vertex is
// weighted 1.0 to bone 0, and bone 0 is named after the attachment node — so
// the pose the actor's clip already computes for `Weapon` moves the weapon,
// with no new per-frame code and no second update path to keep in sync.
//
// The palette maths, given the shader's `world = modelMatrix * (bone * v)` and
// `modelMatrix = actorTransform * meshLocal` (RenderScene, Shaders.metal):
//
//     bone = meshLocal⁻¹ * boneWorld * meshLocal
//     world = actorTransform * meshLocal * meshLocal⁻¹ * boneWorld * meshLocal * v
//           = actorTransform * boneWorld * (meshLocal * v)
//
// which is the weapon's own geometry placed at the bone, in the actor's
// space — exactly what a rigid attachment means. `RenderMesh` composes the
// palette as `rootParentToSkin * currentBone * skinToBone`, so the two halves
// go in those two slots and nothing about the skinning path changes.
//
// The bind matrix uses the skeleton's own rest transform for the node, so a
// model that is never animated (animation disabled, or a clip that failed to
// load) still hangs in the right place instead of collapsing to the origin.
//
// Documented in docs/formats/actors.md.

import Foundation
import simd

nonisolated enum RigidAttachment {
    /// `model` rewritten so every mesh is skinned to the single bone `bone`.
    ///
    /// - Parameters:
    ///   - model: the decoded rigid model — a WEAP world model.
    ///   - bone: the pose-space bone name the meshes ride. Matched by name
    ///     against the animation pose, so it must be spelled as the Havok rig
    ///     spells it (`Weapon`, not `WEAPON`).
    ///   - restTransform: the bone's rest transform in the skeleton's space,
    ///     used for the bind palette. Identity leaves an un-animated
    ///     attachment at the actor's origin, which is a visible, honest
    ///     failure rather than a hidden one.
    static func skinned(
        _ model: Model,
        to bone: String,
        restTransform: float4x4
    ) -> Model {
        Model(
            meshes: model.meshes.map { skinned($0, to: bone, restTransform: restTransform) },
            materials: model.materials,
            skippedShapeCount: model.skippedShapeCount
        )
    }

    /// One mesh bound to `bone`. A mesh that already carries skinning is left
    /// alone: it is rigged geometry that belongs to some other rig, and
    /// overwriting its palette would be a silent corruption rather than an
    /// attachment.
    private static func skinned(
        _ mesh: Mesh,
        to bone: String,
        restTransform: float4x4
    ) -> Mesh {
        guard mesh.skinning == nil else { return mesh }
        let local = mesh.transform
        let inverseLocal = local.inverse
        let skinning = MeshSkinning(
            weights: Array(repeating: SIMD4(1, 0, 0, 0), count: mesh.positions.count),
            boneIndices: Array(repeating: SIMD4(0, 0, 0, 0), count: mesh.positions.count),
            bindPoseMatrices: [inverseLocal * restTransform * local],
            boneNames: [bone],
            rootParentToSkin: inverseLocal,
            skinToBoneMatrices: [local]
        )
        return Mesh(
            name: mesh.name,
            transform: mesh.transform,
            positions: mesh.positions,
            normals: mesh.normals,
            tangents: mesh.tangents,
            bitangents: mesh.bitangents,
            uvs: mesh.uvs,
            colors: mesh.colors,
            indices: mesh.indices,
            materialSlot: mesh.materialSlot,
            skinning: skinning
        )
    }
}
