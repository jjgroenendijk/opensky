// Engine-side geometry types, decoupled from any on-disk layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model()); consumer: the static-mesh render path (todo 2.6).

import Foundation
import simd

/// One drawable chunk: vertex arrays + triangle indices in mesh-local space,
/// the transform into model space, and a material slot resolved against the
/// owning Model. Attribute arrays are either empty or vertex-count sized.
nonisolated struct Mesh {
    let name: String?
    /// Mesh-local -> model-root transform (column vectors, `M * v`; see
    /// docs/decisions/coordinates.md).
    let transform: float4x4
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let tangents: [SIMD3<Float>]
    let bitangents: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    /// RGBA in [0, 1].
    let colors: [SIMD4<Float>]
    /// Flat triangle list, three indices per triangle, all < positions.count.
    let indices: [UInt16]
    /// Index into the owning `Model.materialSlots`.
    let materialSlot: Int
}

/// Material identity of a mesh. For now (todo 2.3) it records which NIF
/// shader/alpha property blocks the shape referenced; 2.4 resolves these
/// into parsed material data. Hashable so shapes sharing properties share
/// one slot.
nonisolated struct MaterialSlot: Hashable {
    let shaderPropertyBlock: Int?
    let alphaPropertyBlock: Int?
}

/// One loaded asset: every drawable mesh plus the material slots they index.
nonisolated struct Model {
    let meshes: [Mesh]
    let materialSlots: [MaterialSlot]
    /// Shapes dropped during flatten (skinned or empty) — surfaced so scene
    /// build (todo 2.7) can report skips instead of silently thinning
    /// geometry.
    let skippedShapeCount: Int
}
