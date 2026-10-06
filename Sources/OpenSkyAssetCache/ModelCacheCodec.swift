// A flattened model as cache bytes: every mesh's vertex arrays, indices, and
// skin streams, and the materials. Loading it skips the NIF parse and flatten.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public enum ModelCacheCodec {
    public static func encode(_ model: Model) -> Data {
        var out = CachePayloadWriter()
        out.int(model.skippedShapeCount)
        out.int(model.editorMarkerShapeCount)
        out.int(model.materials.count)
        model.materials.forEach { encode($0, into: &out) }
        out.int(model.meshes.count)
        model.meshes.forEach { encode($0, into: &out) }
        return out.data
    }

    public static func decode(_ data: Data) throws -> Model {
        var input = CachePayloadReader(data)
        let skipped = try input.int()
        let markers = try input.int()
        let materials = try (0 ..< count(input.int(), in: data))
            .map { _ in try material(&input) }
        let meshes = try (0 ..< count(input.int(), in: data)).map { _ in try mesh(&input) }
        guard input.isAtEnd else { throw CachePayloadError.truncated }
        return Model(
            meshes: meshes, materials: materials, skippedShapeCount: skipped,
            editorMarkerShapeCount: markers
        )
    }

    static func count(_ value: Int, in data: Data) throws -> Int {
        guard value >= 0, value <= data.count else { throw CachePayloadError.badCount(value) }
        return value
    }

    private static func encode(_ material: Material, into out: inout CachePayloadWriter) {
        out.string(material.diffuseTexture)
        out.string(material.normalTexture)
        out.value(material.uvOffset)
        out.value(material.uvScale)
        out.value(material.alpha)
        out.value(material.glossiness)
        out.value(material.specularColor)
        out.value(material.specularStrength)
        out.bool(material.doubleSided)
        out.bool(material.alphaBlend)
        out.array(material.alphaTestThreshold.map { [$0] } ?? [])
    }

    private static func material(_ input: inout CachePayloadReader) throws -> Material {
        let diffuse = try input.string()
        let normal = try input.string()
        let uvOffset = try input.value(SIMD2<Float>.self)
        let uvScale = try input.value(SIMD2<Float>.self)
        let alpha = try input.value(Float.self)
        let glossiness = try input.value(Float.self)
        let specularColor = try input.value(SIMD3<Float>.self)
        let specularStrength = try input.value(Float.self)
        let doubleSided = try input.bool()
        let alphaBlend = try input.bool()
        let threshold = try input.array(Float.self).first
        return Material(
            diffuseTexture: diffuse, normalTexture: normal, uvOffset: uvOffset, uvScale: uvScale,
            alpha: alpha, glossiness: glossiness, specularColor: specularColor,
            specularStrength: specularStrength, doubleSided: doubleSided, alphaBlend: alphaBlend,
            alphaTestThreshold: threshold
        )
    }

    private static func encode(_ mesh: Mesh, into out: inout CachePayloadWriter) {
        out.string(mesh.name)
        out.value(mesh.transform)
        out.array(mesh.positions)
        out.array(mesh.normals)
        out.array(mesh.tangents)
        out.array(mesh.bitangents)
        out.array(mesh.uvs)
        out.array(mesh.colors)
        out.array(mesh.indices)
        out.int(mesh.materialSlot)
        out.bool(mesh.skinning != nil)
        guard let skinning = mesh.skinning else { return }
        out.array(skinning.weights)
        out.array(skinning.boneIndices)
        out.array(skinning.bindPoseMatrices)
        out.strings(skinning.boneNames)
        out.value(skinning.rootParentToSkin)
        out.array(skinning.skinToBoneMatrices)
    }

    private static func mesh(_ input: inout CachePayloadReader) throws -> Mesh {
        let name = try input.string()
        let transform = try input.value(float4x4.self)
        let positions = try input.array(SIMD3<Float>.self)
        let normals = try input.array(SIMD3<Float>.self)
        let tangents = try input.array(SIMD3<Float>.self)
        let bitangents = try input.array(SIMD3<Float>.self)
        let uvs = try input.array(SIMD2<Float>.self)
        let colors = try input.array(SIMD4<Float>.self)
        let indices = try input.array(UInt16.self)
        let slot = try input.int()
        let skinning = try input.bool() ? try skinning(&input) : nil
        return Mesh(
            name: name, transform: transform, positions: positions, normals: normals,
            tangents: tangents, bitangents: bitangents, uvs: uvs, colors: colors, indices: indices,
            materialSlot: slot, skinning: skinning
        )
    }

    private static func skinning(_ input: inout CachePayloadReader) throws -> MeshSkinning {
        let weights = try input.array(SIMD4<Float>.self)
        let boneIndices = try input.array(SIMD4<UInt16>.self)
        let bindPose = try input.array(float4x4.self)
        let names = try input.strings()
        let root = try input.value(float4x4.self)
        let skinToBone = try input.array(float4x4.self)
        return MeshSkinning(
            weights: weights, boneIndices: boneIndices, bindPoseMatrices: bindPose,
            boneNames: names, rootParentToSkin: root, skinToBoneMatrices: skinToBone
        )
    }
}
