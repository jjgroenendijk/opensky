// A texture set and a tint laid over a loaded model, as a head part's TNAM and
// color do, and per-shape texture sets, as a base record's MODS list does. The
// shader multiplies vertex color into the diffuse, so the tint goes into the
// vertex colors and needs no shader change.

import Foundation

nonisolated public struct ModelSurfaceOverride: Hashable, Sendable {
    /// Texture keys as `Material` spells them; nil keeps the model's own.
    public let diffuseTexture: String?
    public let normalTexture: String?
    /// Linear 0...1 RGB, multiplied into every vertex color.
    public let tint: SIMD3<Float>?
    /// Textures for single shapes, laid over the whole-model textures.
    public let shapes: [ShapeTextures]
    /// The actor's skin colour, the tint colour of skin-tint shapes only.
    public let skinTone: SIMD3<Float>?

    /// The textures one named shape draws instead of its own.
    public struct ShapeTextures: Hashable, Sendable {
        public let shapeName: String
        public let diffuseTexture: String?
        public let normalTexture: String?

        public init(shapeName: String, diffuseTexture: String?, normalTexture: String?) {
            self.shapeName = shapeName
            self.diffuseTexture = diffuseTexture
            self.normalTexture = normalTexture
        }
    }

    public init(
        diffuseTexture: String?,
        normalTexture: String?,
        tint: SIMD3<Float>?,
        shapes: [ShapeTextures] = [],
        skinTone: SIMD3<Float>? = nil
    ) {
        self.diffuseTexture = diffuseTexture
        self.normalTexture = normalTexture
        self.tint = tint
        self.shapes = shapes
        self.skinTone = skinTone
    }

    /// `surface` with `skinTone` added, or nil when both are empty.
    public static func skinned(
        _ surface: ModelSurfaceOverride?, skinTone: SIMD3<Float>?
    ) -> ModelSurfaceOverride? {
        guard let skinTone else { return surface }
        return ModelSurfaceOverride(
            diffuseTexture: surface?.diffuseTexture, normalTexture: surface?.normalTexture,
            tint: surface?.tint, shapes: surface?.shapes ?? [], skinTone: skinTone
        )
    }

    public var isEmpty: Bool {
        diffuseTexture == nil && normalTexture == nil && tint == nil && shapes.isEmpty
            && skinTone == nil
    }

    /// Part of a mesh cache key: two overrides that draw alike key alike.
    public var cacheKey: String {
        let tint = tint.map(Self.colorKey) ?? "-"
        let skin = skinTone.map { "|skin:" + Self.colorKey($0) } ?? ""
        let shapes = shapes.map {
            "\($0.shapeName.lowercased())=\($0.diffuseTexture ?? "-"),\($0.normalTexture ?? "-")"
        }
        return "surface:\(diffuseTexture ?? "-")|\(normalTexture ?? "-")|\(tint)" + skin
            + (shapes.isEmpty ? "" : "|shapes:" + shapes.joined(separator: ";"))
    }

    private static func colorKey(_ color: SIMD3<Float>) -> String {
        String(format: "%.4f,%.4f,%.4f", color.x, color.y, color.z)
    }

    /// A shape with its own textures gets a material of its own, because other
    /// shapes may share the material it had.
    public func applied(to model: Model) -> Model {
        var meshes = model.meshes.map { tinted($0, by: tint) }
        var materials = model.materials.map {
            Self.retextured(
                $0,
                diffuse: diffuseTexture,
                normal: normalTexture,
                replacesTint: tint != nil,
                skinTone: $0.tintsSkin ? skinTone : nil
            )
        }
        for index in meshes.indices {
            let mesh = meshes[index]
            guard
                let name = mesh.name?.lowercased(),
                let swap = shapes.first(where: { $0.shapeName.lowercased() == name }),
                materials.indices.contains(mesh.materialSlot)
            else { continue }
            materials.append(Self.retextured(
                materials[mesh.materialSlot],
                diffuse: swap.diffuseTexture,
                normal: swap.normalTexture,
                replacesTint: false,
                skinTone: nil
            ))
            meshes[index] = Self.mesh(mesh, colors: mesh.colors, materialSlot: materials.count - 1)
        }
        return Model(
            meshes: meshes,
            materials: materials,
            skippedShapeCount: model.skippedShapeCount,
            editorMarkerShapeCount: model.editorMarkerShapeCount
        )
    }

    /// An actor's own colour replaces the tint colour the NIF stores. The skin tone
    /// stays a material colour, because the shader blends it unlike a vertex colour.
    private static func retextured(
        _ material: Material,
        diffuse: String?,
        normal: String?,
        replacesTint: Bool,
        skinTone: SIMD3<Float>?
    ) -> Material {
        var shading = material.shading
        if replacesTint {
            shading.tintColor = nil
        }
        if let skinTone {
            shading.tintColor = skinTone
        }
        return Material(
            diffuseTexture: diffuse ?? material.diffuseTexture,
            normalTexture: normal ?? material.normalTexture,
            uvOffset: material.uvOffset,
            uvScale: material.uvScale,
            alpha: material.alpha,
            glossiness: material.glossiness,
            specularColor: material.specularColor,
            specularStrength: material.specularStrength,
            doubleSided: material.doubleSided,
            alphaBlend: material.alphaBlend,
            alphaTestThreshold: material.alphaTestThreshold,
            tintTexture: material.tintTexture,
            tintsSkin: material.tintsSkin,
            shading: shading
        )
    }

    /// A mesh without vertex colors draws white, so it gets the tint itself.
    private func tinted(_ mesh: Mesh, by tint: SIMD3<Float>?) -> Mesh {
        guard let tint else { return mesh }
        let factor = SIMD4<Float>(tint, 1)
        let colors = mesh.colors.isEmpty
            ? Array(repeating: factor, count: mesh.positions.count)
            : mesh.colors.map { $0 * factor }
        return Self.mesh(mesh, colors: colors, materialSlot: mesh.materialSlot)
    }

    private static func mesh(_ mesh: Mesh, colors: [SIMD4<Float>], materialSlot: Int) -> Mesh {
        Mesh(
            name: mesh.name,
            transform: mesh.transform,
            positions: mesh.positions,
            normals: mesh.normals,
            tangents: mesh.tangents,
            bitangents: mesh.bitangents,
            uvs: mesh.uvs,
            colors: colors,
            indices: mesh.indices,
            materialSlot: materialSlot,
            skinning: mesh.skinning
        )
    }
}
