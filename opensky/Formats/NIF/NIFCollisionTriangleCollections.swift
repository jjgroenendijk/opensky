// Alternate NIF collision triangle stores used by
// bhkPackedNiTriStripsShape and bhkNiTriStripsShape.
//
// Reference: NifTools nif.xml (hkPackedNiTriStripsData,
// bhkPackedNiTriStripsShape, bhkNiTriStripsShape, NiTriStripsData).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml

import Foundation
import simd

nonisolated enum NIFCollisionTriangleCollections {
    struct Soup {
        let vertices: [SIMD3<Float>]
        let indices: [UInt32]
    }

    static func decodePacked(data: Data, scale: SIMD3<Float>) throws -> Soup {
        var reader = BinaryReader(data)
        let triangleCount = try checkedCount(
            reader: &reader,
            stride: 8,
            label: "packed triangles"
        )
        var rawTriangles: [[UInt16]] = []
        rawTriangles.reserveCapacity(triangleCount)
        for _ in 0 ..< triangleCount {
            try rawTriangles.append([
                reader.readUInt16(),
                reader.readUInt16(),
                reader.readUInt16()
            ])
            _ = try reader.readUInt16() // welding info
        }

        let vertexCount = try Int(reader.readUInt32())
        let compressed = try reader.readUInt8() != 0
        let stride = compressed ? 6 : 12
        guard vertexCount <= reader.bytesRemaining / stride else {
            throw NIFError.malformed("packed vertex count \(vertexCount) exceeds block size")
        }
        let unitScale = NIFCollisionModel.havokToEngineScale
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vertexCount)
        for _ in 0 ..< vertexCount {
            let point: SIMD3<Float> = if compressed {
                try SIMD3(
                    Float(Float16(bitPattern: reader.readUInt16())),
                    Float(Float16(bitPattern: reader.readUInt16())),
                    Float(Float16(bitPattern: reader.readUInt16()))
                )
            } else {
                try reader.readVector3()
            }
            vertices.append(point * scale * unitScale)
        }

        let subShapeCount = try Int(reader.readUInt16())
        guard subShapeCount <= reader.bytesRemaining / 12 else {
            throw NIFError.malformed(
                "packed sub-shape count \(subShapeCount) exceeds block size"
            )
        }
        reader.skip(subShapeCount * 12)

        var indices: [UInt32] = []
        indices.reserveCapacity(triangleCount * 3)
        for triangle in rawTriangles {
            try appendValidated(triangle, vertexCount: vertexCount, into: &indices)
        }
        return Soup(vertices: vertices, indices: indices)
    }

    static func decodeTriStrips(data: Data, scale: SIMD3<Float>) throws -> Soup {
        var reader = BinaryReader(data)
        _ = try reader.readUInt32() // group ID
        let vertexCount = try Int(reader.readUInt16())
        _ = try reader.readUInt8() // keep flags
        _ = try reader.readUInt8() // compress flags
        let vertices = try readTriStripVertices(
            reader: &reader,
            count: vertexCount,
            scale: scale
        )
        try skipTriStripAttributes(reader: &reader, vertexCount: vertexCount)
        let declaredTriangleCount = try Int(reader.readUInt16())
        let (points, lengths) = try readTriStripPoints(reader: &reader)
        let indices = try stripTriangles(
            points: points,
            lengths: lengths,
            vertexCount: vertexCount
        )
        guard indices.count / 3 == declaredTriangleCount else {
            throw NIFError.malformed(
                "NiTriStrips declares \(declaredTriangleCount) triangles, decoded "
                    + "\(indices.count / 3)"
            )
        }
        return Soup(vertices: vertices, indices: indices)
    }

    private static func readTriStripVertices(
        reader: inout BinaryReader,
        count: Int,
        scale: SIMD3<Float>
    ) throws -> [SIMD3<Float>] {
        guard try reader.readUInt8() != 0 else {
            throw NIFError.malformed("NiTriStripsData has no vertices")
        }
        guard count <= reader.bytesRemaining / 12 else {
            throw NIFError.malformed("strip vertex count \(count) exceeds block size")
        }
        let unitScale = NIFCollisionModel.havokToEngineScale
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(count)
        for _ in 0 ..< count {
            try vertices.append(reader.readVector3() * scale * unitScale)
        }
        return vertices
    }

    private static func skipTriStripAttributes(
        reader: inout BinaryReader,
        vertexCount: Int
    ) throws {
        let dataFlags = try reader.readUInt16()
        _ = try reader.readUInt32() // material CRC
        if try reader.readUInt8() != 0 {
            try skip(reader: &reader, count: vertexCount, stride: 12, label: "normals")
            if dataFlags & 0x1000 != 0 {
                try skip(reader: &reader, count: vertexCount, stride: 24, label: "tangents")
            }
        }
        reader.skip(16) // NiBound
        if try reader.readUInt8() != 0 {
            try skip(reader: &reader, count: vertexCount, stride: 16, label: "colors")
        }
        try skip(
            reader: &reader,
            count: vertexCount * Int(dataFlags & 1),
            stride: 8,
            label: "UVs"
        )
        reader.skip(8) // ConsistencyType + additional data ref
    }

    private static func readTriStripPoints(
        reader: inout BinaryReader
    ) throws -> ([UInt16], [Int]) {
        let stripCount = try Int(reader.readUInt16())
        guard stripCount <= reader.bytesRemaining / 2 else {
            throw NIFError.malformed("NiTriStrips strip count \(stripCount) exceeds block size")
        }
        var lengths: [Int] = []
        lengths.reserveCapacity(stripCount)
        for _ in 0 ..< stripCount {
            try lengths.append(Int(reader.readUInt16()))
        }
        guard try reader.readUInt8() != 0 else {
            throw NIFError.malformed("NiTriStripsData has no point arrays")
        }
        let pointCount = lengths.reduce(0, +)
        guard pointCount <= reader.bytesRemaining / 2 else {
            throw NIFError.malformed("NiTriStrips point count \(pointCount) exceeds block size")
        }
        var points: [UInt16] = []
        points.reserveCapacity(pointCount)
        for _ in 0 ..< pointCount {
            try points.append(reader.readUInt16())
        }
        return (points, lengths)
    }

    private static func stripTriangles(
        points: [UInt16],
        lengths: [Int],
        vertexCount: Int
    ) throws -> [UInt32] {
        var output: [UInt32] = []
        var cursor = 0
        for length in lengths {
            guard length >= 3 else {
                throw NIFError.malformed("NiTriStrips length \(length) is below 3")
            }
            for triangle in 0 ..< length - 2 {
                let first = points[cursor + triangle]
                let second = points[cursor + triangle + 1]
                let third = points[cursor + triangle + 2]
                let ordered = triangle.isMultiple(of: 2)
                    ? [first, second, third]
                    : [first, third, second]
                try appendValidated(ordered, vertexCount: vertexCount, into: &output)
            }
            cursor += length
        }
        return output
    }

    private static func appendValidated(
        _ triangle: [UInt16],
        vertexCount: Int,
        into output: inout [UInt32]
    ) throws {
        guard triangle.allSatisfy({ Int($0) < vertexCount }) else {
            throw NIFError.malformed("collision triangle exceeds \(vertexCount) vertices")
        }
        output.append(contentsOf: triangle.map(UInt32.init))
    }

    private static func skip(
        reader: inout BinaryReader,
        count: Int,
        stride: Int,
        label: String
    ) throws {
        guard count >= 0, count <= reader.bytesRemaining / stride else {
            throw NIFError.malformed("\(label) exceed NiTriStripsData block size")
        }
        reader.skip(count * stride)
    }

    private static func checkedCount(
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
