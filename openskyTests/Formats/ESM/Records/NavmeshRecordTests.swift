// NAVM / NVNM decoder tests over synthetic in-code records only. Covers the
// geometry layout, the interior/exterior parent union, the XXXX-extended
// oversized payload NVNM is the reason the engine handles at all, and the
// malformed-payload policy: truncation and out-of-range indices throw rather
// than surviving into the pathing graph.

import Foundation
@testable import opensky
import simd
import Testing

struct NavmeshRecordTests {
    @Test func decodesTwoTriangleInteriorMesh() throws {
        let navmesh = try Navmesh(record: NavmeshFixture.record(NavmeshFixture.navmRecord(
            formID: 0x101, editorID: "TestNavmesh", geometry: NavmeshFixture.twoTriangleMesh()
        )))

        #expect(navmesh.formID == FormID(0x101))
        #expect(navmesh.editorID == "TestNavmesh")
        #expect(navmesh.geometry.version == 12)
        #expect(navmesh.geometry.location == .interior(cell: FormID(0x1234)))
        #expect(navmesh.geometry.vertices.count == 4)
        #expect(navmesh.geometry.vertices[3] == SIMD3(1, 1, 0))
        #expect(navmesh.geometry.triangles.count == 2)
        #expect(navmesh.geometry.triangles[0].vertices == SIMD3(0, 1, 2))
        // The two triangles name each other across their shared edge.
        #expect(navmesh.geometry.triangles[0].neighbors == SIMD3(-1, 1, -1))
        #expect(navmesh.geometry.triangles[1].neighbors == SIMD3(-1, -1, 0))
        #expect(navmesh.geometry.edgeLinks.isEmpty)
        #expect(navmesh.geometry.doorLinks.isEmpty)
    }

    /// A non-null parent worldspace switches the union to a grid pair stored Y
    /// first — the rule xEdit's `wbNVNMParentDecider` uses, against UESP's
    /// claim that the switch is worldspace == 0x3C.
    @Test func decodesExteriorGridLocation() throws {
        let geometry = NavmeshFixture.geometry(world: 0x3C, grid: (x: 6, y: -2))
        let navmesh = try Navmesh(record: NavmeshFixture.record(
            NavmeshFixture.navmRecord(geometry: geometry)
        ))

        #expect(navmesh.geometry.location == .exterior(world: FormID(0x3C), x: 6, y: -2))
    }

    @Test func decodesEdgeAndDoorLinks() throws {
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [NavmeshFixture.Triangle(
                // Edge 0-1 is a link: its neighbour indexes the edge-link
                // array, not the triangle array.
                vertices: SIMD3(0, 1, 2), neighbors: SIMD3(0, -1, -1), flags: 0x0001
            )],
            edgeLinks: [NavmeshFixture.EdgeLink(type: 1, navmesh: 0xABC, triangle: 0)],
            doorLinks: [NavmeshFixture.DoorLink(triangle: 0, door: 0xDEF)]
        )
        let navmesh = try Navmesh(record: NavmeshFixture.record(
            NavmeshFixture.navmRecord(geometry: geometry)
        ))

        let link = try #require(navmesh.geometry.edgeLinks.first)
        #expect(link.type == .ledgeUp)
        #expect(link.navmesh == FormID(0xABC))
        #expect(link.triangle == 0)
        let door = try #require(navmesh.geometry.doorLinks.first)
        #expect(door.door == FormID(0xDEF))
        #expect(navmesh.geometry.triangles[0].flags.contains(.edge01Link))
    }

    @Test func decodesCoverAndGridTallies() throws {
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))],
            coverTriangles: [0],
            divisor: 2,
            gridSquares: [[0], [], [0], []]
        )
        let navmesh = try Navmesh(record: NavmeshFixture.record(
            NavmeshFixture.navmRecord(geometry: geometry)
        ))

        #expect(navmesh.geometry.coverTriangleCount == 1)
        #expect(navmesh.geometry.gridDivisor == 2)
        #expect(navmesh.geometry.gridSize == SIMD2(64, 64))
        #expect(navmesh.geometry.boundsMax == SIMD3(1, 1, 1))
        #expect(navmesh.geometry.gridTriangleIndexCount == 2)
    }

    /// The case `ESMField`'s XXXX handling exists for: a payload past the
    /// 16-bit field-size ceiling, which every large vanilla navmesh is.
    @Test func decodesOversizedPayloadThroughXXXXExtension() throws {
        // 6000 vertices is 72 000 payload bytes before the arrays around them.
        let vertices = (0 ..< 6000).map { SIMD3(Float($0), 0, 0) }
        let geometry = NavmeshFixture.geometry(
            vertices: vertices,
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))]
        )
        #expect(geometry.count > 0xFFFF)
        let record = try NavmeshFixture.record(NavmeshFixture.navmRecord(geometry: geometry))
        // One folded field, not an XXXX marker plus a zero-sized NVNM.
        #expect(try record.fields().map(\.type) == ["NVNM"])

        let navmesh = try Navmesh(record: record)
        #expect(navmesh.geometry.vertices.count == 6000)
        #expect(navmesh.geometry.vertices[5999].x == 5999)
    }

    // MARK: - Malformed input

    @Test func throwsOnTruncatedVertexArray() throws {
        // Cut the payload down to one vertex' worth of bytes behind a count
        // that claims two, so the count is rejected before it is trusted.
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)]
        ).prefix(36)
        let record = try NavmeshFixture.record(NavmeshFixture.navmRecord(geometry: geometry))

        #expect(throws: (any Error).self) { try Navmesh(record: record) }
    }

    @Test func throwsOnTruncatedTriangleArray() throws {
        // 60 bytes reaches the end of the triangle count; the 16-byte triangle
        // it announces is left half-written.
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))]
        ).prefix(68)
        let record = try NavmeshFixture.record(NavmeshFixture.navmRecord(geometry: geometry))

        #expect(throws: (any Error).self) { try Navmesh(record: record) }
    }

    /// A count that cannot fit in the bytes left must be rejected before it is
    /// used to size an allocation.
    @Test func throwsOnImplausibleVertexCount() throws {
        var geometry = Data()
        geometry.appendUInt32(12)
        geometry.appendUInt32(0) // pathing-cell CRC marker
        geometry.appendUInt32(0) // interior: null worldspace
        geometry.appendUInt32(0x1234) // parent cell
        geometry.appendUInt32(0xFFFF_FF00) // vertex count, wildly past the end
        let record = try NavmeshFixture.record(NavmeshFixture.navmRecord(geometry: geometry))

        #expect(throws: ESMError.self) { try Navmesh(record: record) }
    }

    @Test func throwsOnOutOfRangeVertexIndex() throws {
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 7))]
        )
        let record = try NavmeshFixture.record(NavmeshFixture.navmRecord(geometry: geometry))

        #expect(throws: ESMError.self) { try Navmesh(record: record) }
    }

    @Test func throwsOnOutOfRangeNeighborIndex() throws {
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [NavmeshFixture.Triangle(
                vertices: SIMD3(0, 1, 2), neighbors: SIMD3(4, -1, -1)
            )]
        )
        let record = try NavmeshFixture.record(NavmeshFixture.navmRecord(geometry: geometry))

        #expect(throws: ESMError.self) { try Navmesh(record: record) }
    }

    @Test func throwsOnOutOfRangeDoorTriangle() throws {
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))],
            doorLinks: [NavmeshFixture.DoorLink(triangle: 3, door: 0xDEF)]
        )
        let record = try NavmeshFixture.record(NavmeshFixture.navmRecord(geometry: geometry))

        #expect(throws: ESMError.self) { try Navmesh(record: record) }
    }

    /// The deliberate exception to the range-checking rule: an edge link's
    /// triangle indexes the navmesh the link names, so a value past the local
    /// triangle count is ordinary vanilla data, not corruption. Checking it
    /// locally rejected over half the Whiterun-area navmeshes.
    @Test func acceptsEdgeLinkTriangleBeyondTheLocalTriangleCount() throws {
        let geometry = NavmeshFixture.geometry(
            vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))],
            edgeLinks: [NavmeshFixture.EdgeLink(navmesh: 0xABC, triangle: 466)]
        )
        let navmesh = try Navmesh(record: NavmeshFixture.record(
            NavmeshFixture.navmRecord(geometry: geometry)
        ))

        #expect(navmesh.geometry.edgeLinks.first?.triangle == 466)
    }

    @Test func throwsOnMissingGeometryField() throws {
        let record = try NavmeshFixture.record(ESMFixture.record(
            "NAVM", formID: 0x102, data: ESMFixture.field("EDID", ESMFixture.zstring("Empty"))
        ))

        #expect(throws: ESMError.self) { try Navmesh(record: record) }
    }

    @Test func throwsOnWrongRecordType() throws {
        let record = try NavmeshFixture.record(ESMFixture.record(
            "NAVI", formID: 0x103, data: Data()
        ))

        #expect(throws: ESMError.self) { try Navmesh(record: record) }
    }
}
