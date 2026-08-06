// Alternate NIF collision triangle stores used by
// bhkPackedNiTriStripsShape and bhkNiTriStripsShape. The second of those two
// lives in NIFCollisionTriStrips.swift; the shared `Soup` and the bounds
// helpers at the bottom of this file are what they have in common.
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
        /// `SkyrimHavokMaterial` for this soup's surface (issue #358), from the
        /// sub-shape the triangles belong to. Nil when the block declares no
        /// sub-shapes to take it from.
        let material: UInt32?

        init(vertices: [SIMD3<Float>], indices: [UInt32], material: UInt32? = nil) {
            self.vertices = vertices
            self.indices = indices
            self.material = material
        }
    }

    /// One `hkSubPartData`: the material plus the run of vertices it covers.
    private struct SubShape {
        let material: UInt32
        let vertexCount: Int
    }

    /// A packed strip shape partitions its vertices between sub-shapes, and
    /// each sub-shape names its own material. The soups this returns are that
    /// partition: one per sub-shape that any triangle actually falls in, in
    /// sub-shape order, sharing the block's single vertex array.
    static func decodePacked(data: Data, scale: SIMD3<Float>) throws -> [Soup] {
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

        let subShapes = try readSubShapes(reader: &reader)
        return try partitioned(
            triangles: rawTriangles,
            vertices: vertices,
            subShapes: subShapes
        )
    }

    private static func readSubShapes(
        reader: inout BinaryReader
    ) throws -> [SubShape] {
        let count = try Int(reader.readUInt16())
        guard count <= reader.bytesRemaining / 12 else {
            throw NIFError.malformed("packed sub-shape count \(count) exceeds block size")
        }
        var subShapes: [SubShape] = []
        subShapes.reserveCapacity(count)
        for _ in 0 ..< count {
            reader.skip(4) // HavokFilter: layer/flags/group, not a material
            let vertexCount = try Int(reader.readUInt32())
            try subShapes.append(SubShape(
                material: reader.readUInt32(),
                vertexCount: vertexCount
            ))
        }
        return subShapes
    }

    /// Splits the triangle list by the sub-shape its first vertex falls in. A
    /// vanilla triangle never straddles two sub-shapes; one that did would be
    /// assigned by that first vertex rather than dropped, because a surface
    /// with a debatable material still has to stop the player.
    private static func partitioned(
        triangles: [[UInt16]],
        vertices: [SIMD3<Float>],
        subShapes: [SubShape]
    ) throws -> [Soup] {
        guard !subShapes.isEmpty else {
            var indices: [UInt32] = []
            indices.reserveCapacity(triangles.count * 3)
            for triangle in triangles {
                try appendValidated(triangle, vertexCount: vertices.count, into: &indices)
            }
            return indices.isEmpty ? [] : [Soup(vertices: vertices, indices: indices)]
        }
        var bounds: [Int] = []
        var total = 0
        for subShape in subShapes {
            total += max(subShape.vertexCount, 0)
            bounds.append(total)
        }
        var grouped = [[UInt32]](repeating: [], count: subShapes.count)
        for triangle in triangles {
            var indices: [UInt32] = []
            try appendValidated(triangle, vertexCount: vertices.count, into: &indices)
            let owner = bounds.firstIndex { Int(indices[0]) < $0 } ?? subShapes.count - 1
            grouped[owner].append(contentsOf: indices)
        }
        return zip(subShapes, grouped).compactMap { subShape, indices in
            indices.isEmpty ? nil : Soup(
                vertices: vertices,
                indices: indices,
                material: subShape.material
            )
        }
    }

    static func appendValidated(
        _ triangle: [UInt16],
        vertexCount: Int,
        into output: inout [UInt32]
    ) throws {
        guard triangle.allSatisfy({ Int($0) < vertexCount }) else {
            throw NIFError.malformed("collision triangle exceeds \(vertexCount) vertices")
        }
        output.append(contentsOf: triangle.map(UInt32.init))
    }

    static func skip(
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
