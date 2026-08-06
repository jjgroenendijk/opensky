// bhkNiTriStripsShape's NiTriStripsData half, split from the packed-strips
// decoder so each stays inside the strict type-body limit. The two share
// `Soup` and the bounds helpers on NIFCollisionTriangleCollections, which are
// internal rather than private for exactly that reason.
//
// Reference: NifTools nif.xml (bhkNiTriStripsShape, NiTriStripsData,
// NiGeometryData).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml

import Foundation
import simd

nonisolated extension NIFCollisionTriangleCollections {
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
        // NiGeometryData's tail: Consistency Flags is a ConsistencyType, which
        // nif.xml stores as a ushort rather than a uint, then the
        // AbstractAdditionalGeometryData ref. Reading it as four bytes put
        // every field after it two bytes late, which is what made the three
        // vanilla `bhkNiTriStripsShape` meshes fail to decode (issue #376) —
        // the only shape class in the install that reaches this code, so
        // nothing else covered the mistake.
        reader.skip(2) // Consistency Flags
        reader.skip(4) // Additional Data ref
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
}
