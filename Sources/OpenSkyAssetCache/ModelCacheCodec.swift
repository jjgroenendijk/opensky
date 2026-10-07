// A flattened model as cache bytes. The payload starts with a small layout block, then
// each mesh's vertices and indices ready for a GPU buffer, then the whole model: every
// mesh's arrays, skin streams, and materials. See docs/engine/fast-mesh-loading.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public enum ModelCacheCodec {
    /// GPU blocks start on this boundary inside the payload, which starts on one too.
    static let blockAlignment = 16

    public static func encode(_ model: Model) -> Data {
        var blocks = Data()
        var ranges: [ReadyMeshRanges] = []
        for mesh in model.meshes {
            let vertices = append(InterleavedVertexLayout.interleave(mesh), to: &blocks)
            let indices = append(mesh.indices, to: &blocks)
            ranges.append(ReadyMeshRanges(vertices: vertices, indices: indices))
        }
        let whole = encodeModel(model)
        let layout = ReadyModelLayoutCodec.encode(
            model, ranges: ranges, modelRange: blocks.count ..< blocks.count + whole.count
        )
        var out = BinaryWriter()
        out.writeUInt64(UInt64(layout.count))
        out.write(layout)
        out.write(Data(count: padding(after: out.count)))
        out.write(blocks)
        out.write(whole)
        return out.data
    }

    public static func decode(_ data: Data) throws -> Model {
        let layout = try decodeLayout(data)
        let (base, range) = (data.startIndex, layout.modelRange)
        guard range.upperBound <= data.count else { throw CachePayloadError.truncated }
        return try decodeModel(data[(base + range.lowerBound) ..< (base + range.upperBound)])
    }

    /// The layout block, from the first `layoutByteCount(head:)` bytes of the payload.
    public static func decodeLayout(_ head: Data) throws -> ReadyModelLayout {
        guard let count = layoutByteCount(head: head), count <= head.count else {
            throw CachePayloadError.truncated
        }
        let block = head[(head.startIndex + 8) ..< (head.startIndex + count)]
        return try ReadyModelLayoutCodec.decode(block, dataStart: count + padding(after: count))
    }

    /// Payload bytes from its start to the end of the layout block; nil before 8 bytes.
    public static func layoutByteCount(head: Data) -> Int? {
        var reader = BinaryReader(head)
        guard let length = try? reader.readUInt64(), length <= UInt64(Int32.max) else {
            return nil
        }
        return 8 + Int(length)
    }

    static func padding(after count: Int) -> Int {
        (blockAlignment - count % blockAlignment) % blockAlignment
    }

    private static func append(
        _ values: [some BitwiseCopyable],
        to data: inout Data
    ) -> Range<Int> {
        let start = data.count
        values.withUnsafeBytes { data.append(contentsOf: $0) }
        let end = data.count
        data.append(Data(count: padding(after: end)))
        return start ..< end
    }

    private static func encodeModel(_ model: Model) -> Data {
        var out = CachePayloadWriter()
        out.int(model.skippedShapeCount)
        out.int(model.editorMarkerShapeCount)
        out.int(model.materials.count)
        model.materials.forEach { encode($0, into: &out) }
        out.int(model.meshes.count)
        model.meshes.forEach { encode($0, into: &out) }
        return out.data
    }

    private static func decodeModel(_ data: Data) throws -> Model {
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

    static func encode(_ material: Material, into out: inout CachePayloadWriter) {
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

    static func material(_ input: inout CachePayloadReader) throws -> Material {
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
