// An actor's weight blends two copies of a body mesh: `_0.nif` (thin) and
// `_1.nif` (heavy), shape for shape and vertex for vertex.
// See docs/engine/actor-resolution.md.

import Foundation
import simd

nonisolated public enum BodyWeightBlend {
    /// The thin sibling of a heavy model path, or nil when `path` has no `_1.nif` ending.
    public static func thinPath(forHeavy path: String) -> String? {
        let suffix = "_1.nif"
        guard path.lowercased().hasSuffix(suffix) else { return nil }
        return String(path.dropLast(suffix.count)) + "_0.nif"
    }

    /// `heavy` with each position and normal moved toward `thin` by `1 - weight`.
    /// `weight` is 0 (thin) to 1 (heavy). A shape whose vertex count differs keeps
    /// the heavy vertices, because the two files then do not pair.
    public static func blend(thin: Model, heavy: Model, weight: Float) -> Model {
        let amount = min(max(weight, 0), 1)
        let meshes = heavy.meshes.enumerated().map { index, mesh in
            guard
                thin.meshes.indices.contains(index),
                thin.meshes[index].positions.count == mesh.positions.count
            else { return mesh }
            return blended(mesh, thin: thin.meshes[index], amount: amount)
        }
        return Model(
            meshes: meshes,
            materials: heavy.materials,
            skippedShapeCount: heavy.skippedShapeCount,
            editorMarkerShapeCount: heavy.editorMarkerShapeCount
        )
    }

    private static func blended(_ heavy: Mesh, thin: Mesh, amount: Float) -> Mesh {
        let positions = zip(thin.positions, heavy.positions).map { mix($0, $1, t: amount) }
        let normals = thin.normals.count == heavy.normals.count
            ? zip(thin.normals, heavy.normals).map { thinNormal, heavyNormal in
                let normal = mix(thinNormal, heavyNormal, t: amount)
                return length_squared(normal) > 1e-12 ? normalize(normal) : heavyNormal
            }
            : heavy.normals
        return Mesh(
            name: heavy.name,
            transform: heavy.transform,
            positions: positions,
            normals: normals,
            tangents: heavy.tangents,
            bitangents: heavy.bitangents,
            uvs: heavy.uvs,
            colors: heavy.colors,
            indices: heavy.indices,
            materialSlot: heavy.materialSlot,
            skinning: heavy.skinning
        )
    }
}
