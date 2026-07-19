// Skyrim bhkCompressedMeshShapeData -> triangle soups. MOPP is an
// acceleration structure only; geometry comes from big triangles plus
// quantized chunks. Each chunk vertex is translation + ushort/1000, then an
// optional chunk transform. Strip winding alternates; trailing indices are
// independent triangles.
//
// References:
// - NifTools nif.xml (bhkCompressedMeshShapeData, bhkCMSChunk,
//   bhkCMSBigTri, bhkQsTransform).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// - nifly/PyNifly collision extraction (chunk dequantization + strips).
//   https://github.com/BadDogSkyrim/PyNifly/blob/main/NiflyDLL/NiflyWrapper.cpp

import Foundation
import simd

nonisolated enum NIFCompressedCollisionMesh {
    struct Soup {
        let vertices: [SIMD3<Float>]
        let indices: [UInt32]
    }

    struct ChunkTransform {
        let translation: SIMD3<Float>
        let rotation: simd_quatf

        func apply(to point: SIMD3<Float>) -> SIMD3<Float> {
            rotation.act(point) + translation
        }
    }

    static func decode(data: Data, shapeScale: SIMD3<Float>) throws -> [Soup] {
        var reader = BinaryReader(data)
        try readHeader(reader: &reader)
        try skipIntegerArray(reader: &reader, label: "32-bit materials")
        try skipIntegerArray(reader: &reader, label: "16-bit materials")
        try skipIntegerArray(reader: &reader, label: "8-bit materials")
        try skipChunkMaterials(reader: &reader)
        _ = try reader.readUInt32() // named material count; array is not serialized
        let transforms = try readTransforms(reader: &reader)
        let bigVertices = try readBigVertices(reader: &reader, scale: shapeScale)
        let bigIndices = try readBigTriangles(reader: &reader, vertexCount: bigVertices.count)
        let chunks = try readChunks(
            reader: &reader,
            transforms: transforms,
            scale: shapeScale
        )
        _ = try reader.readUInt32() // unused Num Convex Piece A

        var soups: [Soup] = []
        if !bigIndices.isEmpty {
            soups.append(Soup(vertices: bigVertices, indices: bigIndices))
        }
        soups.append(contentsOf: chunks)
        return soups
    }

    private static func readHeader(reader: inout BinaryReader) throws {
        _ = try reader.readUInt32() // bits per index
        _ = try reader.readUInt32() // bits per winding index
        _ = try reader.readUInt32() // winding mask
        _ = try reader.readUInt32() // index mask
        _ = try reader.readFloat32() // quantization error
        _ = try reader.readVector4() // AABB min
        _ = try reader.readVector4() // AABB max
        _ = try reader.readUInt8() // welding type
        _ = try reader.readUInt8() // material type
    }

    private static func skipIntegerArray(
        reader: inout BinaryReader,
        label: String
    ) throws {
        let count = try checkedCount(
            reader: &reader,
            stride: 4,
            label: label
        )
        reader.skip(count * 4)
    }

    private static func skipChunkMaterials(reader: inout BinaryReader) throws {
        let count = try checkedCount(
            reader: &reader,
            stride: 8,
            label: "chunk materials"
        )
        reader.skip(count * 8) // Skyrim material uint32 + HavokFilter
    }

    private static func readTransforms(
        reader: inout BinaryReader
    ) throws -> [ChunkTransform] {
        let count = try checkedCount(
            reader: &reader,
            stride: 32,
            label: "chunk transforms"
        )
        var transforms: [ChunkTransform] = []
        transforms.reserveCapacity(count)
        for _ in 0 ..< count {
            let translation = try reader.readVector4().xyz
            let value = try reader.readVector4()
            let length = simd_length(value)
            guard length.isFinite, length > .ulpOfOne else {
                throw NIFError.malformed("zero or non-finite compressed-mesh quaternion")
            }
            transforms.append(ChunkTransform(
                translation: translation,
                rotation: simd_quatf(vector: value / length)
            ))
        }
        return transforms
    }

    private static func readBigVertices(
        reader: inout BinaryReader,
        scale: SIMD3<Float>
    ) throws -> [SIMD3<Float>] {
        let count = try checkedCount(reader: &reader, stride: 16, label: "big vertices")
        let unitScale = NIFCollisionModel.havokToEngineScale
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(count)
        for _ in 0 ..< count {
            try vertices.append(reader.readVector4().xyz * scale * unitScale)
        }
        return vertices
    }

    private static func readBigTriangles(
        reader: inout BinaryReader,
        vertexCount: Int
    ) throws -> [UInt32] {
        let count = try checkedCount(reader: &reader, stride: 12, label: "big triangles")
        var indices: [UInt32] = []
        indices.reserveCapacity(count * 3)
        for _ in 0 ..< count {
            let triangle = try [
                reader.readUInt16(),
                reader.readUInt16(),
                reader.readUInt16()
            ]
            _ = try reader.readUInt32() // material table index
            _ = try reader.readUInt16() // welding info
            try appendValidated(triangle, vertexCount: vertexCount, into: &indices)
        }
        return indices
    }

    static func checkedCount(
        reader: inout BinaryReader,
        stride: Int,
        label: String
    ) throws -> Int {
        let count = try Int(reader.readUInt32())
        guard count <= reader.bytesRemaining / stride else {
            throw NIFError.malformed("\(label) count \(count) exceeds block size")
        }
        return count
    }
}
