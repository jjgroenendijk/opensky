// A texture set and a tint laid over a loaded model, as a head part's TNAM and
// color do. The shader multiplies vertex color into the diffuse, so the tint
// goes into the vertex colors and needs no shader change.

import Foundation

nonisolated public struct ModelSurfaceOverride: Hashable, Sendable {
    /// Texture keys as `Material` spells them; nil keeps the model's own.
    public let diffuseTexture: String?
    public let normalTexture: String?
    /// Linear 0...1 RGB, multiplied into every vertex color.
    public let tint: SIMD3<Float>?

    public init(diffuseTexture: String?, normalTexture: String?, tint: SIMD3<Float>?) {
        self.diffuseTexture = diffuseTexture
        self.normalTexture = normalTexture
        self.tint = tint
    }

    public var isEmpty: Bool {
        diffuseTexture == nil && normalTexture == nil && tint == nil
    }

    /// Part of a mesh cache key: two overrides that draw alike key alike.
    public var cacheKey: String {
        let tint = tint.map { String(format: "%.4f,%.4f,%.4f", $0.x, $0.y, $0.z) } ?? "-"
        return "surface:\(diffuseTexture ?? "-")|\(normalTexture ?? "-")|\(tint)"
    }

    public func applied(to model: Model) -> Model {
        Model(
            meshes: model.meshes.map(tinted),
            materials: model.materials.map(retextured),
            skippedShapeCount: model.skippedShapeCount,
            editorMarkerShapeCount: model.editorMarkerShapeCount
        )
    }

    private func retextured(_ material: Material) -> Material {
        Material(
            diffuseTexture: diffuseTexture ?? material.diffuseTexture,
            normalTexture: normalTexture ?? material.normalTexture,
            uvOffset: material.uvOffset,
            uvScale: material.uvScale,
            alpha: material.alpha,
            glossiness: material.glossiness,
            specularColor: material.specularColor,
            specularStrength: material.specularStrength,
            doubleSided: material.doubleSided,
            alphaBlend: material.alphaBlend,
            alphaTestThreshold: material.alphaTestThreshold
        )
    }

    /// A mesh without vertex colors draws white, so it gets the tint itself.
    private func tinted(_ mesh: Mesh) -> Mesh {
        guard let tint else { return mesh }
        let factor = SIMD4<Float>(tint, 1)
        let colors = mesh.colors.isEmpty
            ? Array(repeating: factor, count: mesh.positions.count)
            : mesh.colors.map { $0 * factor }
        return Mesh(
            name: mesh.name,
            transform: mesh.transform,
            positions: mesh.positions,
            normals: mesh.normals,
            tangents: mesh.tangents,
            bitangents: mesh.bitangents,
            uvs: mesh.uvs,
            colors: colors,
            indices: mesh.indices,
            materialSlot: mesh.materialSlot,
            skinning: mesh.skinning
        )
    }
}
