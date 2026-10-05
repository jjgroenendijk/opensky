// Rigid bone attachment: a scene bakes placement transforms at build time, but
// a drawn weapon must follow the hand each frame. So the weapon becomes a
// skinned mesh with one bone named after the attachment node, and the actor's
// pose moves it. The math is in docs/engine/actor-resolution.md.

import Foundation
import simd

nonisolated public enum RigidAttachment: Sendable {
    /// `model` rewritten so every mesh is skinned to the single bone `bone`.
    /// `bone` must be spelled as the Havok rig spells it (`Weapon`). An
    /// identity `restTransform` leaves an unanimated model at the actor origin.
    public static func skinned(
        _ model: Model,
        to bone: String,
        restTransform: float4x4
    ) -> Model {
        Model(
            meshes: model.meshes.map { skinned($0, to: bone, restTransform: restTransform) },
            materials: model.materials,
            skippedShapeCount: model.skippedShapeCount,
            editorMarkerShapeCount: model.editorMarkerShapeCount
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
