// Quantized bhkCMSChunk reconstruction split from container-array decode.
// Reference + conversion: docs/formats/nif-collision.md.

import Foundation
import simd

nonisolated extension NIFCompressedCollisionMesh {
    static func readChunks(
        reader: inout BinaryReader,
        transforms: [ChunkTransform],
        scale: SIMD3<Float>
    ) throws -> [Soup] {
        let count = try Int(reader.readUInt32())
        guard count <= reader.bytesRemaining / 40 else {
            throw NIFError.malformed("compressed chunk count \(count) exceeds block size")
        }
        var chunks: [Soup] = []
        chunks.reserveCapacity(count)
        for _ in 0 ..< count {
            try chunks.append(readChunk(
                reader: &reader,
                transforms: transforms,
                scale: scale
            ))
        }
        return chunks
    }

    private static func readChunk(
        reader: inout BinaryReader,
        transforms: [ChunkTransform],
        scale: SIMD3<Float>
    ) throws -> Soup {
        let translation = try reader.readVector4().xyz
        _ = try reader.readUInt32() // material index
        let reference = try reader.readUInt16()
        let transformIndex = try reader.readUInt16()
        guard reference == .max else {
            throw NIFError.unsupported("compressed chunk references chunk \(reference)")
        }
        let vertexCount = try readVertexCount(reader: &reader)
        let transform = try resolvedTransform(index: transformIndex, in: transforms)
        let vertices = try readVertices(
            reader: &reader,
            count: vertexCount,
            translation: translation,
            transform: transform,
            scale: scale
        )
        let sourceIndices = try readUInt16Array(
            reader: &reader,
            label: "compressed indices"
        )
        let strips = try readUInt16Array(
            reader: &reader,
            label: "compressed strips"
        ).map(Int.init)
        let weldingCount = try checkedCount(
            reader: &reader,
            stride: 2,
            label: "compressed welding info"
        )
        reader.skip(weldingCount * 2)
        return try Soup(
            vertices: vertices,
            indices: triangles(source: sourceIndices, strips: strips, vertexCount: vertexCount)
        )
    }

    private static func readVertexCount(reader: inout BinaryReader) throws -> Int {
        let componentCount = try Int(reader.readUInt32())
        guard componentCount % 3 == 0, componentCount <= reader.bytesRemaining / 2 else {
            throw NIFError.malformed(
                "compressed vertex component count \(componentCount) is invalid"
            )
        }
        return componentCount / 3
    }

    private static func resolvedTransform(
        index: UInt16,
        in transforms: [ChunkTransform]
    ) throws -> ChunkTransform? {
        guard index != .max else { return nil }
        guard Int(index) < transforms.count else {
            throw NIFError.malformed("compressed transform index \(index) out of range")
        }
        return transforms[Int(index)]
    }

    private static func readVertices(
        reader: inout BinaryReader,
        count: Int,
        translation: SIMD3<Float>,
        transform: ChunkTransform?,
        scale: SIMD3<Float>
    ) throws -> [SIMD3<Float>] {
        let unitScale = NIFCollisionModel.havokToEngineScale
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(count)
        for _ in 0 ..< count {
            var point = try SIMD3<Float>(
                Float(reader.readUInt16()),
                Float(reader.readUInt16()),
                Float(reader.readUInt16())
            ) / 1000 + translation
            if let transform {
                point = transform.apply(to: point)
            }
            vertices.append(point * scale * unitScale)
        }
        return vertices
    }

    private static func readUInt16Array(
        reader: inout BinaryReader,
        label: String
    ) throws -> [UInt16] {
        let count = try checkedCount(reader: &reader, stride: 2, label: label)
        var values: [UInt16] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            try values.append(reader.readUInt16())
        }
        return values
    }

    private static func triangles(
        source: [UInt16],
        strips: [Int],
        vertexCount: Int
    ) throws -> [UInt32] {
        let stripIndexCount = strips.reduce(0, +)
        guard
            stripIndexCount <= source.count,
            (source.count - stripIndexCount) % 3 == 0
        else {
            throw NIFError.malformed("compressed strip lengths do not partition indices")
        }
        var output: [UInt32] = []
        var cursor = 0
        for length in strips {
            try appendStrip(
                source: source,
                cursor: cursor,
                length: length,
                vertexCount: vertexCount,
                output: &output
            )
            cursor += length
        }
        while cursor < source.count {
            try appendValidated(
                Array(source[cursor ..< cursor + 3]),
                vertexCount: vertexCount,
                into: &output
            )
            cursor += 3
        }
        return output
    }

    private static func appendStrip(
        source: [UInt16],
        cursor: Int,
        length: Int,
        vertexCount: Int,
        output: inout [UInt32]
    ) throws {
        guard length >= 3 else {
            throw NIFError.malformed("compressed strip length \(length) is below 3")
        }
        for triangle in 0 ..< length - 2 {
            let first = source[cursor + triangle]
            let second = source[cursor + triangle + 1]
            let third = source[cursor + triangle + 2]
            let ordered = triangle.isMultiple(of: 2)
                ? [first, second, third]
                : [first, third, second]
            try appendValidated(ordered, vertexCount: vertexCount, into: &output)
        }
    }

    static func appendValidated(
        _ triangle: [UInt16],
        vertexCount: Int,
        into output: inout [UInt32]
    ) throws {
        guard triangle.count == 3, triangle.allSatisfy({ Int($0) < vertexCount }) else {
            throw NIFError.malformed("collision triangle index exceeds \(vertexCount) vertices")
        }
        output.append(contentsOf: triangle.map(UInt32.init))
    }
}
