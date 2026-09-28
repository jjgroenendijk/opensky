// The M16 gate's synthetic records and geometry (issue #203).
//
// Two navmesh sheets and one guard's package stack, built in code from the
// documented layouts and decoded through the production parsers. No packfile
// bytes, no extracted records, no positions taken from the install (AGENTS.md
// "Legal & IP boundary").
//
// The stack is two scheduled packages and no fallback, deliberately. A guard
// with an unscheduled catch-all would always have something selected, and the
// gate's claim is that the *schedule* decides: at nine in the morning the patrol
// wins, at nine at night the sleep package does, and the change happens because
// the clock moved rather than because a test set it.

import Foundation
@testable import opensky
import simd

@MainActor
enum M16AcceptanceFixture {
    static let patrolPackage = FormID(0x100)
    static let sleepPackage = FormID(0x101)
    /// The patrol runs from eight in the morning for twelve hours; sleep takes
    /// the rest of the day. Between them they cover the clock with no gap and no
    /// overlap, so "which package now" always has exactly one answer.
    static let patrolStartHour: Int8 = 8
    static let patrolDurationMinutes: UInt32 = 720
    static let sleepStartHour: Int8 = 20
    static let sleepDurationMinutes: UInt32 = 720

    /// One flat rectangular navmesh sheet, 200 by 40 units from `origin` on +X,
    /// with `door` linked to whichever triangle the door position falls in.
    static func sheet(id: UInt32, origin: Float, door: UInt32) throws -> Navmesh {
        let vertices = sheetVertices(origin: origin)
        var triangles = sheetTriangles()
        connectSharedEdges(in: &triangles)
        let doorTriangle = triangleIndex(
            containing: SIMD2(origin + doorOffsetX, doorOffsetY),
            vertices: vertices,
            triangles: triangles
        )
        return try NavigationRuntimeFixture.navmesh(
            id: id,
            vertices: vertices,
            triangles: triangles,
            doorLinks: [NavmeshFixture.DoorLink(triangle: Int16(doorTriangle), door: door)]
        )
    }

    /// The guard's two-package stack behind one NPC_ base.
    static func packageStore() throws -> PackageStore {
        let patrol = try package(
            id: patrolPackage.rawValue,
            editorID: "M16GuardPatrol",
            schedule: schedule(hour: patrolStartHour, duration: patrolDurationMinutes),
            procedureNames: ["Travel"]
        )
        let sleep = try package(
            id: sleepPackage.rawValue,
            editorID: "M16GuardSleep",
            schedule: schedule(hour: sleepStartHour, duration: sleepDurationMinutes),
            procedureNames: ["Sleep"]
        )
        let base = try actorBase(
            id: M16AcceptanceChain.guardBase.rawValue,
            packages: [patrolPackage.rawValue, sleepPackage.rawValue]
        )
        return PackageStore(
            packages: [patrol, sleep],
            actorTemplates: ActorTemplateResolver(
                actors: [M16AcceptanceChain.guardBase.rawValue: base], leveledActors: [:]
            )
        )
    }

    // MARK: - Geometry

    /// Where the door stands inside its own sheet, which is the same offset in
    /// both so the two sheets are mirror images of each other.
    private static let doorOffsetX: Float = 180
    private static let doorOffsetY: Float = 20
    private static let spacing: Float = 20
    private static let columns = 10
    private static let rows = 2

    private static func sheetVertices(origin: Float) -> [SIMD3<Float>] {
        var vertices: [SIMD3<Float>] = []
        for row in 0 ... rows {
            for column in 0 ... columns {
                vertices.append(SIMD3(
                    origin + Float(column) * spacing, Float(row) * spacing, 0
                ))
            }
        }
        return vertices
    }

    private static func sheetTriangles() -> [NavmeshFixture.Triangle] {
        var triangles: [NavmeshFixture.Triangle] = []
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let first = UInt16(row * (columns + 1) + column)
                let third = UInt16((row + 1) * (columns + 1) + column)
                triangles.append(NavmeshFixture.Triangle(
                    vertices: SIMD3(first, first + 1, third)
                ))
                triangles.append(NavmeshFixture.Triangle(
                    vertices: SIMD3(first + 1, third + 1, third)
                ))
            }
        }
        return triangles
    }

    /// Pairs every shared edge, so the sheet is one connected mesh rather than
    /// forty islands A* cannot cross between.
    private static func connectSharedEdges(in triangles: inout [NavmeshFixture.Triangle]) {
        var owners: [UInt32: (triangle: Int, edge: Int)] = [:]
        for index in triangles.indices {
            for edge in 0 ..< 3 {
                let key = edgeKey(triangles[index].vertices, edge: edge)
                if let owner = owners[key] {
                    triangles[index].neighbors[edge] = Int16(owner.triangle)
                    triangles[owner.triangle].neighbors[owner.edge] = Int16(index)
                } else {
                    owners[key] = (index, edge)
                }
            }
        }
    }

    private static func edgeKey(_ vertices: SIMD3<UInt16>, edge: Int) -> UInt32 {
        let first = vertices[edge]
        let second = vertices[(edge + 1) % 3]
        let low = UInt32(min(first, second))
        let high = UInt32(max(first, second))
        return low << 16 | high
    }

    /// Which triangle a ground point falls in, by 2D barycentric containment.
    /// Falls back to zero, which a fixture that stopped covering its own door
    /// would then fail loudly on rather than silently linking nothing.
    private static func triangleIndex(
        containing point: SIMD2<Float>,
        vertices: [SIMD3<Float>],
        triangles: [NavmeshFixture.Triangle]
    ) -> Int {
        for (index, triangle) in triangles.enumerated() {
            let corners = (0 ..< 3).map { corner -> SIMD2<Float> in
                let vertex = vertices[Int(triangle.vertices[corner])]
                return SIMD2(vertex.x, vertex.y)
            }
            if contains(point, corners: corners) {
                return index
            }
        }
        return 0
    }

    private static func contains(_ point: SIMD2<Float>, corners: [SIMD2<Float>]) -> Bool {
        let signs = (0 ..< 3).map { index -> Float in
            let first = corners[index]
            let second = corners[(index + 1) % 3]
            let edge = second - first
            let offset = point - first
            return edge.x * offset.y - edge.y * offset.x
        }
        return signs.allSatisfy { $0 >= 0 } || signs.allSatisfy { $0 <= 0 }
    }

    // MARK: - Records

    private static func schedule(hour: Int8, duration: UInt32) -> Package.Schedule {
        Package.Schedule(
            month: -1, dayOfWeek: -1, date: 0, hour: hour, minute: 0, durationMinutes: duration
        )
    }

    private static func package(
        id: UInt32,
        editorID: String,
        schedule: Package.Schedule,
        procedureNames: [String]
    ) throws -> Package {
        Package(
            formID: FormID(id),
            editorID: editorID,
            general: Package.GeneralData(
                flags: [],
                kind: .package,
                interruptOverride: 0,
                preferredSpeed: .walk,
                interruptFlags: 0
            ),
            schedule: schedule,
            conditions: ConditionList(),
            template: nil,
            dataInputs: [],
            procedureTypes: procedureNames,
            scriptData: ScriptData(ownerType: "PACK")
        )
    }

    private static func actorBase(id: UInt32, packages: [UInt32]) throws -> ActorBase {
        var acbs = Data(count: 18)
        acbs.appendUInt16(0)
        acbs.appendUInt32(0)
        var fields = ESMFixture.field("ACBS", acbs)
        for package in packages {
            var data = Data()
            data.appendUInt32(package)
            fields += ESMFixture.field("PKID", data)
        }
        return try ActorBase(
            record: PackageFixture.parse(ESMFixture.record("NPC_", formID: id, data: fields)),
            localized: false
        )
    }
}
