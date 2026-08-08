// NVNM payload decode. The byte layout, the citations and the skipped list
// live in the header of Navmesh.swift; this file is the reader.
//
// Two rules shape the code. Every count is a uint32 read straight out of the
// file, so it is checked against the bytes actually remaining before anything
// is allocated — a corrupt count must throw, not ask for gigabytes. And every
// index into the vertex or triangle array is range-checked here, because an
// out-of-range index that survives decode becomes a crash in the pathing graph
// (16.2) far from the record that caused it.

import Foundation
import simd

/// Reader helpers shared by NVNM geometry and the NVMI index entries, which
/// spell counted arrays and the parent-cell union identically.
nonisolated enum NavmeshDecoding {
    /// uint32 element count, rejected when the array it introduces cannot fit
    /// in what is left of the payload.
    static func readCount(
        _ reader: inout BinaryReader,
        elementSize: Int,
        of what: String
    ) throws -> Int {
        let count = try Int(reader.readUInt32())
        guard count >= 0, count <= reader.bytesRemaining / elementSize else {
            throw ESMError.malformed(
                "navmesh \(what) count \(count) exceeds \(reader.bytesRemaining) bytes remaining"
            )
        }
        return count
    }

    static func readVector3(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        try SIMD3(reader.readFloat32(), reader.readFloat32(), reader.readFloat32())
    }

    /// The "pathing cell" struct: a constant CRC marker, the parent
    /// worldspace, then either the parent CELL or the exterior grid square.
    /// A null worldspace is what makes it an interior (xEdit
    /// `wbNVNMParentDecider`); the grid pair is stored Y first.
    static func readLocation(_ reader: inout BinaryReader) throws -> NavmeshLocation {
        _ = try reader.readUInt32() // CRC hash of "PathingCell", a constant
        let world = try FormID(reader.readUInt32())
        guard !world.isNull else {
            return try .interior(cell: FormID(reader.readUInt32()))
        }
        let y = try Int32(Int16(bitPattern: reader.readUInt16()))
        let x = try Int32(Int16(bitPattern: reader.readUInt16()))
        return .exterior(world: world, x: x, y: y)
    }
}

nonisolated struct NavmeshGeometry: Sendable {
    /// Per-triangle flag bits (xEdit `wbNavmeshTriangleFlags`). The three edge
    /// bits say the matching neighbour index is an edge-link into another
    /// navmesh rather than a triangle in this one.
    struct TriangleFlags: OptionSet, Equatable, Sendable {
        let rawValue: UInt16

        static let edge01Link = TriangleFlags(rawValue: 1 << 0)
        static let edge12Link = TriangleFlags(rawValue: 1 << 1)
        static let edge20Link = TriangleFlags(rawValue: 1 << 2)
        static let deleted = TriangleFlags(rawValue: 1 << 3)
        static let noLargeCreatures = TriangleFlags(rawValue: 1 << 4)
        static let overlapping = TriangleFlags(rawValue: 1 << 5)
        static let preferred = TriangleFlags(rawValue: 1 << 6)
        static let water = TriangleFlags(rawValue: 1 << 9)
        static let door = TriangleFlags(rawValue: 1 << 10)
        static let found = TriangleFlags(rawValue: 1 << 11)
    }

    /// One walkable face. `neighbors` holds the triangle bordering edge 0-1,
    /// 1-2 and 2-0 in that order, or -1 where the edge borders nothing. Where
    /// the matching `TriangleFlags` edge bit is set the value indexes this
    /// navmesh's edge-link array instead, which is why it is not resolved here.
    struct Triangle: Equatable, Sendable {
        static let encodedSize = 16

        let vertices: SIMD3<UInt16>
        let neighbors: SIMD3<Int16>
        let flags: TriangleFlags
        /// Cover nibbles packed two-edges-to-a-uint16. Retained raw: xEdit's
        /// own comment says the documented flag names are wrong and nothing
        /// in OpenSky reads cover yet.
        let coverFlags: UInt16
    }

    /// How an actor crosses from this navmesh into a neighbouring one.
    enum EdgeLinkType: UInt32, Sendable {
        case portal = 0
        case ledgeUp = 1
        case ledgeDown = 2
        case enableDisablePortal = 3
    }

    struct EdgeLink: Equatable, Sendable {
        static let encodedSize = 10

        /// Nil for a value outside the documented set; `rawType` keeps it.
        let type: EdgeLinkType?
        let rawType: UInt32
        /// The NAVM on the other side of the boundary.
        let navmesh: FormID
        /// Triangle index inside `navmesh` — the far side of the link, not a
        /// triangle in this mesh. The census established that: validating it
        /// against the local triangle array rejected more than half the
        /// vanilla navmeshes in the Whiterun area, always on this field, with
        /// values far past the local count. xEdit agrees by omission — it
        /// gives the door link's triangle a `wbTriangleLinksTo` callback and
        /// this one none. Nothing local can range-check it, so it is not
        /// checked here; the pathing graph resolves it against the navmesh it
        /// names (16.2, issue #200).
        let triangle: Int16
    }

    /// A triangle standing at a door threshold, paired with the DOOR REFR an
    /// actor passing over it teleports through.
    struct DoorLink: Equatable, Sendable {
        static let encodedSize = 10

        let triangle: Int16
        let door: FormID
    }

    /// NVNM version; 12 in every vanilla record.
    let version: UInt32
    let location: NavmeshLocation
    let vertices: [SIMD3<Float>]
    let triangles: [Triangle]
    let edgeLinks: [EdgeLink]
    let doorLinks: [DoorLink]
    /// Cover-triangle list length. The list itself is validated and dropped.
    let coverTriangleCount: Int
    /// Navmesh-grid divisor: the grid is divisor x divisor squares. xEdit
    /// treats a value over 12 as "no grid follows"; this decoder does the same.
    let gridDivisor: UInt32
    /// Extent of one grid square, in game units.
    let gridSize: SIMD2<Float>
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
    /// Total triangle indices across every grid square, kept for the census;
    /// the per-square lists themselves are validated and dropped.
    let gridTriangleIndexCount: Int

    init(data: Data) throws {
        var reader = BinaryReader(data)
        version = try reader.readUInt32()
        location = try NavmeshDecoding.readLocation(&reader)
        vertices = try Self.readVertices(&reader)
        triangles = try Self.readTriangles(&reader)
        edgeLinks = try Self.readEdgeLinks(&reader)
        doorLinks = try Self.readDoorLinks(&reader)
        coverTriangleCount = try Self.readTriangleIndices(&reader, of: "cover triangle").count
        gridDivisor = try reader.readUInt32()
        gridSize = try SIMD2(reader.readFloat32(), reader.readFloat32())
        boundsMin = try NavmeshDecoding.readVector3(&reader)
        boundsMax = try NavmeshDecoding.readVector3(&reader)
        gridTriangleIndexCount = try Self.readGrid(&reader, divisor: gridDivisor)
        try validate()
    }

    private static func readVertices(_ reader: inout BinaryReader) throws -> [SIMD3<Float>] {
        let count = try NavmeshDecoding.readCount(&reader, elementSize: 12, of: "vertex")
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(count)
        for _ in 0 ..< count {
            try vertices.append(NavmeshDecoding.readVector3(&reader))
        }
        return vertices
    }

    private static func readTriangles(_ reader: inout BinaryReader) throws -> [Triangle] {
        let count = try NavmeshDecoding.readCount(
            &reader, elementSize: Triangle.encodedSize, of: "triangle"
        )
        var triangles: [Triangle] = []
        triangles.reserveCapacity(count)
        for _ in 0 ..< count {
            let vertices = try SIMD3(
                reader.readUInt16(), reader.readUInt16(), reader.readUInt16()
            )
            let neighbors = try SIMD3(
                Int16(bitPattern: reader.readUInt16()),
                Int16(bitPattern: reader.readUInt16()),
                Int16(bitPattern: reader.readUInt16())
            )
            try triangles.append(Triangle(
                vertices: vertices,
                neighbors: neighbors,
                flags: TriangleFlags(rawValue: reader.readUInt16()),
                coverFlags: reader.readUInt16()
            ))
        }
        return triangles
    }

    private static func readEdgeLinks(_ reader: inout BinaryReader) throws -> [EdgeLink] {
        let count = try NavmeshDecoding.readCount(
            &reader, elementSize: EdgeLink.encodedSize, of: "edge link"
        )
        var links: [EdgeLink] = []
        links.reserveCapacity(count)
        for _ in 0 ..< count {
            let rawType = try reader.readUInt32()
            try links.append(EdgeLink(
                type: EdgeLinkType(rawValue: rawType),
                rawType: rawType,
                navmesh: FormID(reader.readUInt32()),
                triangle: Int16(bitPattern: reader.readUInt16())
            ))
        }
        return links
    }

    private static func readDoorLinks(_ reader: inout BinaryReader) throws -> [DoorLink] {
        let count = try NavmeshDecoding.readCount(
            &reader, elementSize: DoorLink.encodedSize, of: "door link"
        )
        var links: [DoorLink] = []
        links.reserveCapacity(count)
        for _ in 0 ..< count {
            let triangle = try Int16(bitPattern: reader.readUInt16())
            _ = try reader.readUInt32() // CRC hash of "PathingDoor", a constant
            try links.append(DoorLink(triangle: triangle, door: FormID(reader.readUInt32())))
        }
        return links
    }

    /// A counted int16 triangle-index list. Returned rather than stored so the
    /// caller can range-check it and keep only the tally.
    private static func readTriangleIndices(
        _ reader: inout BinaryReader,
        of what: String
    ) throws -> [Int16] {
        let count = try NavmeshDecoding.readCount(&reader, elementSize: 2, of: what)
        var indices: [Int16] = []
        indices.reserveCapacity(count)
        for _ in 0 ..< count {
            try indices.append(Int16(bitPattern: reader.readUInt16()))
        }
        return indices
    }

    /// The divisor^2 per-square triangle lists, consumed for their tally.
    /// A divisor outside 0...12 means no lists follow, matching xEdit's
    /// `wbNavmeshGridCounter`.
    private static func readGrid(_ reader: inout BinaryReader, divisor: UInt32) throws -> Int {
        guard divisor <= 12 else { return 0 }
        var total = 0
        for _ in 0 ..< (divisor * divisor) {
            total += try readTriangleIndices(&reader, of: "grid square").count
        }
        return total
    }

    /// Every index the payload carries that points at something local,
    /// checked against the array it points into. An edge whose triangle flag
    /// marks it as an edge link indexes `edgeLinks` instead of `triangles`, so
    /// it is checked against that. An edge link's own triangle index is the
    /// one thing not checked here — it belongs to the navmesh it names.
    private func validate() throws {
        for triangle in triangles {
            for vertex in [triangle.vertices.x, triangle.vertices.y, triangle.vertices.z]
                where Int(vertex) >= vertices.count
            {
                throw ESMError.malformed(
                    "navmesh vertex index \(vertex) beyond \(vertices.count) vertices"
                )
            }
            try validate(triangle: triangle)
        }
        for link in doorLinks {
            try validate(index: link.triangle, of: "door link")
        }
    }

    private func validate(triangle: Triangle) throws {
        let linkBits: [TriangleFlags] = [.edge01Link, .edge12Link, .edge20Link]
        for edge in 0 ..< 3 {
            let neighbor = triangle.neighbors[edge]
            guard neighbor >= 0 else { continue }
            let limit = triangle.flags.contains(linkBits[edge]) ? edgeLinks.count : triangles.count
            guard Int(neighbor) < limit else {
                throw ESMError.malformed(
                    "navmesh edge \(edge) neighbour \(neighbor) beyond \(limit) entries"
                )
            }
        }
    }

    private func validate(index: Int16, of what: String) throws {
        guard index >= 0 else { return } // -1 means "no triangle"
        guard Int(index) < triangles.count else {
            throw ESMError.malformed(
                "navmesh \(what) triangle \(index) beyond \(triangles.count) triangles"
            )
        }
    }
}
