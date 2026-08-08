// Synthetic NVNM / NVMI payload builders for the navmesh decoder tests. Built
// in code from the published layout — never extracted game files (AGENTS.md
// "Legal & IP boundary").
//
// Layout: UESP "Skyrim Mod:Mod File Format" subpages /NAVM, /NVNM Field,
// /NAVI, /NVMI Field, cross-checked against xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas. See docs/formats/navmesh.md.

import Foundation
@testable import opensky
import simd

enum NavmeshFixture {
    /// One triangle as the fixture spells it, before packing.
    struct Triangle {
        var vertices: SIMD3<UInt16>
        var neighbors: SIMD3<Int16> = SIMD3(repeating: -1)
        var flags: UInt16 = 0
        var coverFlags: UInt16 = 0
    }

    struct EdgeLink {
        var type: UInt32 = 0
        var navmesh: UInt32
        var triangle: Int16
    }

    struct DoorLink {
        var triangle: Int16
        var door: UInt32
    }

    /// Parses fixture bytes back into the single record they encode.
    static func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    /// A whole NVNM payload. `world` null makes it an interior addressed by
    /// `cell`; otherwise the exterior grid pair is written, Y first.
    static func geometry(
        version: UInt32 = 12,
        world: UInt32 = 0,
        cell: UInt32 = 0x1234,
        grid: (x: Int16, y: Int16) = (0, 0),
        vertices: [SIMD3<Float>] = [],
        triangles: [Triangle] = [],
        edgeLinks: [EdgeLink] = [],
        doorLinks: [DoorLink] = [],
        coverTriangles: [Int16] = [],
        divisor: UInt32 = 0,
        gridSquares: [[Int16]] = []
    ) -> Data {
        var data = Data()
        data.appendUInt32(version)
        data.append(location(world: world, cell: cell, grid: grid))
        data.appendUInt32(UInt32(vertices.count))
        for vertex in vertices {
            data.appendFloat32(vertex.x)
            data.appendFloat32(vertex.y)
            data.appendFloat32(vertex.z)
        }
        data.appendUInt32(UInt32(triangles.count))
        for triangle in triangles {
            data.append(packed(triangle))
        }
        data.appendUInt32(UInt32(edgeLinks.count))
        for link in edgeLinks {
            data.appendUInt32(link.type)
            data.appendUInt32(link.navmesh)
            data.appendUInt16(UInt16(bitPattern: link.triangle))
        }
        data.appendUInt32(UInt32(doorLinks.count))
        for link in doorLinks {
            data.appendUInt16(UInt16(bitPattern: link.triangle))
            data.appendUInt32(pathingDoorCRC)
            data.appendUInt32(link.door)
        }
        data.append(indexList(coverTriangles))
        data.append(navmeshGrid(divisor: divisor, squares: gridSquares))
        return data
    }

    /// NAVM record wrapping a NVNM payload. Payloads over 64 KB have to travel
    /// through the `XXXX` size extension, which is exactly the case NVNM was
    /// the original reason for.
    static func navmRecord(
        formID: UInt32 = 0x100,
        flags: UInt32 = 0,
        editorID: String? = nil,
        geometry: Data,
        forceLongField: Bool = false
    ) -> Data {
        var fields = Data()
        if let editorID {
            fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        }
        fields += forceLongField || geometry.count > 0xFFFF
            ? ESMFixture.longField("NVNM", geometry)
            : ESMFixture.field("NVNM", geometry)
        return ESMFixture.record("NAVM", formID: formID, flags: flags, data: fields)
    }

    /// One NVMI entry.
    static func info(
        navmesh: UInt32,
        flags: UInt32 = 0,
        location approximate: SIMD3<Float> = SIMD3(1, 2, 3),
        preferredPercent: Float = 0,
        edgeLinks: [UInt32] = [],
        preferredEdgeLinks: [UInt32] = [],
        doors: [UInt32] = [],
        island: Bool = false,
        world: UInt32 = 0,
        cell: UInt32 = 0x1234,
        grid: (x: Int16, y: Int16) = (0, 0)
    ) -> Data {
        var data = Data()
        data.appendUInt32(navmesh)
        data.appendUInt32(flags)
        data.appendFloat32(approximate.x)
        data.appendFloat32(approximate.y)
        data.appendFloat32(approximate.z)
        data.appendFloat32(preferredPercent)
        data.append(formIDList(edgeLinks))
        data.append(formIDList(preferredEdgeLinks))
        data.appendUInt32(UInt32(doors.count))
        for door in doors {
            data.appendUInt32(pathingDoorCRC)
            data.appendUInt32(door)
        }
        data.append(UInt8(island ? 1 : 0))
        if island {
            data.append(islandData())
        }
        data.append(location(world: world, cell: cell, grid: grid))
        return ESMFixture.field("NVMI", data)
    }

    /// NAVI record: NVER, the NVMI entries, and optionally NVSI deletions.
    static func naviRecord(
        formID: UInt32 = 0x10,
        recordFlags: UInt32 = 0,
        version: UInt32 = 0x0C,
        infos: Data,
        deleted: [UInt32] = []
    ) -> Data {
        var nver = Data()
        nver.appendUInt32(version)
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestNavi"))
            + ESMFixture.field("NVER", nver)
            + infos
        if !deleted.isEmpty {
            var payload = Data()
            for id in deleted {
                payload.appendUInt32(id)
            }
            fields += ESMFixture.field("NVSI", payload)
        }
        return ESMFixture.record("NAVI", formID: formID, flags: recordFlags, data: fields)
    }

    /// TES4 plus a NAVI top group holding `records`.
    static func plugin(naviRecords: Data) -> Data {
        ESMFixture.tes4() + ESMFixture.topGroup("NAVI", contents: naviRecords)
    }

    /// A cell-children group (type 6) with a temporary-children group (type 9)
    /// holding `records`, parsed back into the `ESMGroup` the walk takes.
    static func cellChildren(parent: UInt32 = 0x2B, temporary records: Data) throws -> ESMGroup {
        let bytes = ESMFixture.childGroup(
            parent: parent,
            groupType: 6,
            contents: ESMFixture.childGroup(parent: parent, groupType: 9, contents: records)
        )
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .group(group)? = children.first else {
            throw ESMError.malformed("fixture did not produce a group")
        }
        return group
    }

    /// Two triangles sharing the edge between vertices 1 and 2 — the smallest
    /// mesh with a real neighbour relationship in it.
    static func twoTriangleMesh() -> Data {
        geometry(
            vertices: [
                SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0)
            ],
            triangles: [
                Triangle(vertices: SIMD3(0, 1, 2), neighbors: SIMD3(-1, 1, -1)),
                Triangle(vertices: SIMD3(1, 3, 2), neighbors: SIMD3(-1, -1, 0))
            ]
        )
    }

    // MARK: - Pieces

    /// The Creation Kit writes the CRC32 of "PathingCell" / "PathingDoor" as a
    /// constant marker. The decoder skips both, so any value serves here.
    private static let pathingCellCRC: UInt32 = 0x1122_3344
    private static let pathingDoorCRC: UInt32 = 0x5566_7788

    private static func location(world: UInt32, cell: UInt32, grid: (x: Int16, y: Int16)) -> Data {
        var data = Data()
        data.appendUInt32(pathingCellCRC)
        data.appendUInt32(world)
        if world == 0 {
            data.appendUInt32(cell)
        } else {
            data.appendUInt16(UInt16(bitPattern: grid.y))
            data.appendUInt16(UInt16(bitPattern: grid.x))
        }
        return data
    }

    private static func packed(_ triangle: Triangle) -> Data {
        var data = Data()
        for index in 0 ..< 3 {
            data.appendUInt16(triangle.vertices[index])
        }
        for index in 0 ..< 3 {
            data.appendUInt16(UInt16(bitPattern: triangle.neighbors[index]))
        }
        data.appendUInt16(triangle.flags)
        data.appendUInt16(triangle.coverFlags)
        return data
    }

    private static func indexList(_ indices: [Int16]) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(indices.count))
        for index in indices {
            data.appendUInt16(UInt16(bitPattern: index))
        }
        return data
    }

    private static func formIDList(_ ids: [UInt32]) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(ids.count))
        for id in ids {
            data.appendUInt32(id)
        }
        return data
    }

    private static func navmeshGrid(divisor: UInt32, squares: [[Int16]]) -> Data {
        var data = Data()
        data.appendUInt32(divisor)
        data.appendFloat32(64) // grid size X
        data.appendFloat32(64) // grid size Y
        for value in [Float(0), 0, 0, 1, 1, 1] {
            data.appendFloat32(value) // bounds minimum then maximum
        }
        for square in squares {
            data.append(indexList(square))
        }
        return data
    }

    /// The island summary block the decoder consumes and discards: bounds,
    /// one triangle, three vertices.
    private static func islandData() -> Data {
        var data = Data()
        for value in [Float(0), 0, 0, 1, 1, 1] {
            data.appendFloat32(value)
        }
        data.appendUInt32(1)
        for index: UInt16 in 0 ..< 3 {
            data.appendUInt16(index)
        }
        data.appendUInt32(3)
        for value in [Float(0), 0, 0, 1, 0, 0, 0, 1, 0] {
            data.appendFloat32(value)
        }
        return data
    }
}
