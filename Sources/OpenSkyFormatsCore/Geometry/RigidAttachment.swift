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
    /// A mesh skinned to bones the actor lacks (`actorHasBone` false), such as a
    /// bow and its string, is first baked into its bind shape.
    public static func skinned(
        _ model: Model,
        to bone: String,
        restTransform: float4x4,
        actorHasBone: (String) -> Bool = { _ in true }
    ) -> Model {
        Model(
            meshes: model.meshes.map { mesh in
                let ownRig = mesh.skinning.map { !$0.boneNames.allSatisfy(actorHasBone) } ?? false
                return skinned(
                    ownRig ? bakedBindPose(mesh) : mesh,
                    to: bone, restTransform: restTransform, local: mesh.transform
                )
            },
            materials: model.materials,
            skippedShapeCount: model.skippedShapeCount,
            editorMarkerShapeCount: model.editorMarkerShapeCount
        )
    }

    /// One mesh of an object bound to the node it sits under. The mesh transform
    /// becomes relative to the node, so the rest pose draws it where it was.
    public static func skinned(_ mesh: Mesh, toNode bone: String, nodeRest: float4x4) -> Mesh {
        skinned(mesh, to: bone, restTransform: nodeRest, local: nodeRest.inverse * mesh.transform)
    }

    /// `mesh` with its skin removed and each vertex placed where the bind palette
    /// puts it. A rigid mesh is returned as is.
    static func bakedBindPose(_ mesh: Mesh) -> Mesh {
        guard let skin = mesh.skinning, skin.weights.count == mesh.positions.count else {
            return mesh
        }
        let palette = skin.bindPoseMatrices
        func blend(_ vertex: Int) -> float4x4 {
            var matrix = float4x4()
            let weights = skin.weights[vertex]
            let bones = vertex < skin.boneIndices.count ? skin.boneIndices[vertex] : .zero
            for slot in 0 ..< 4 where weights[slot] > 0 && Int(bones[slot]) < palette.count {
                matrix += weights[slot] * palette[Int(bones[slot])]
            }
            return matrix
        }
        let blends = mesh.positions.indices.map(blend)
        func moved(_ vectors: [SIMD3<Float>], w: Float) -> [SIMD3<Float>] {
            guard vectors.count == blends.count else { return vectors }
            return zip(vectors, blends).map { vector, matrix in
                let out = matrix * SIMD4(vector, w)
                let moved = SIMD3(out.x, out.y, out.z)
                guard w == 0 else { return moved }
                let length = simd_length(moved)
                return length > 0 ? moved / length : vector
            }
        }
        return Mesh(
            name: mesh.name,
            transform: mesh.transform,
            positions: moved(mesh.positions, w: 1),
            normals: moved(mesh.normals, w: 0),
            tangents: moved(mesh.tangents, w: 0),
            bitangents: moved(mesh.bitangents, w: 0),
            uvs: mesh.uvs,
            colors: mesh.colors,
            indices: mesh.indices,
            materialSlot: mesh.materialSlot
        )
    }

    /// One mesh bound to `bone`. A mesh that already carries skinning is left
    /// alone: it is rigged geometry that belongs to some other rig, and
    /// overwriting its palette would be a silent corruption rather than an
    /// attachment.
    private static func skinned(
        _ mesh: Mesh,
        to bone: String,
        restTransform: float4x4,
        local: float4x4
    ) -> Mesh {
        guard mesh.skinning == nil else { return mesh }
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
            transform: local,
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
