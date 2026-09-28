// Synthetic runtime navigation fixtures. Geometry is constructed from the
// documented NAVM layout in code and decoded through the production parser;
// no game bytes enter the test target.

@testable import opensky
import simd

@MainActor
enum NavigationRuntimeFixture {
    static func navmesh(
        id: UInt32,
        vertices: [SIMD3<Float>],
        triangles: [NavmeshFixture.Triangle],
        edgeLinks: [NavmeshFixture.EdgeLink] = [],
        doorLinks: [NavmeshFixture.DoorLink] = []
    ) throws -> Navmesh {
        let geometry = NavmeshFixture.geometry(
            vertices: vertices,
            triangles: triangles,
            edgeLinks: edgeLinks,
            doorLinks: doorLinks
        )
        return try Navmesh(record: NavmeshFixture.record(
            NavmeshFixture.navmRecord(formID: id, geometry: geometry)
        ))
    }

    static func grid(id: UInt32, columns: Int, rows: Int, spacing: Float = 10) throws -> Navmesh {
        let vertices = gridVertices(columns: columns, rows: rows, spacing: spacing)
        var triangles = gridTriangles(columns: columns, rows: rows)
        connectSharedEdges(in: &triangles)
        return try navmesh(id: id, vertices: vertices, triangles: triangles)
    }

    static func scene(
        location: CellSceneLocation,
        navmeshes: [Navmesh],
        sequence: UInt64 = 0,
        doors: [PlacedDoor] = [],
        interactions: [FormID: PlacedInteraction] = [:]
    ) -> CellScene {
        CellStreamerTests.cellScene(
            location: location,
            doors: doors,
            interactions: interactions,
            stateSequence: sequence,
            navmeshes: navmeshes
        )
    }

    static func placedDoor(
        reference: UInt32,
        destination: UInt32,
        position: SIMD3<Float>
    ) -> PlacedDoor {
        PlacedDoor(
            reference: FormID(reference),
            position: position,
            destination: PlacedReference.TeleportDestination(
                door: FormID(destination),
                placement: PlacedReference.Placement(
                    position: position,
                    rotation: .zero
                ),
                flags: []
            )
        )
    }

    static func doorInteraction(
        reference: UInt32,
        position: SIMD3<Float>
    ) -> PlacedInteraction {
        CellStreamerTests.interaction(reference: reference, position: position)
    }

    private static func gridVertices(
        columns: Int,
        rows: Int,
        spacing: Float
    ) -> [SIMD3<Float>] {
        var vertices: [SIMD3<Float>] = []
        for row in 0 ... rows {
            for column in 0 ... columns {
                vertices.append(SIMD3(Float(column) * spacing, Float(row) * spacing, 0))
            }
        }
        return vertices
    }

    private static func gridTriangles(
        columns: Int,
        rows: Int
    ) -> [NavmeshFixture.Triangle] {
        var triangles: [NavmeshFixture.Triangle] = []
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let first = UInt16(row * (columns + 1) + column)
                let second = first + 1
                let third = UInt16((row + 1) * (columns + 1) + column)
                let fourth = third + 1
                triangles.append(NavmeshFixture.Triangle(vertices: SIMD3(
                    first, second, third
                )))
                triangles.append(NavmeshFixture.Triangle(vertices: SIMD3(
                    second, fourth, third
                )))
            }
        }
        return triangles
    }

    private static func connectSharedEdges(
        in triangles: inout [NavmeshFixture.Triangle]
    ) {
        var owners: [UInt32: (triangle: Int, edge: Int)] = [:]
        for triangleIndex in triangles.indices {
            for edge in 0 ..< 3 {
                let key = edgeKey(triangles[triangleIndex].vertices, edge: edge)
                if let owner = owners[key] {
                    triangles[triangleIndex].neighbors[edge] = Int16(owner.triangle)
                    triangles[owner.triangle].neighbors[owner.edge] = Int16(triangleIndex)
                } else {
                    owners[key] = (triangleIndex, edge)
                }
            }
        }
    }

    private static func edgeKey(_ vertices: SIMD3<UInt16>, edge: Int) -> UInt32 {
        let ends: (UInt16, UInt16) = switch edge {
        case 0: (vertices.x, vertices.y)
        case 1: (vertices.y, vertices.z)
        default: (vertices.z, vertices.x)
        }
        let low = UInt32(min(ends.0, ends.1))
        let high = UInt32(max(ends.0, ends.1))
        return low << 16 | high
    }
}
