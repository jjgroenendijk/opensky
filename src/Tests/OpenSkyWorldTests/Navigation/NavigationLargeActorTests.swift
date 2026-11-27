// Large-actor pathing and the navmesh spot search over synthetic in-code geometry.

@testable import OpenSkyCells
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyNavigation
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
struct NavigationLargeActorTests {
    private static func found(_ result: NavigationPathResult) -> Bool {
        if case .path = result {
            return true
        }
        return false
    }

    /// Two triangles share an edge; the second is marked "no large creatures".
    private static func graph() throws -> RuntimeNavigationGraph {
        let noLarge = UInt16(NavmeshGeometry.TriangleFlags.noLargeCreatures.rawValue)
        let mesh = try NavigationRuntimeFixture.navmesh(
            id: 0x100,
            vertices: [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0), SIMD3(10, 10, 0)],
            triangles: [
                NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2), neighbors: SIMD3(-1, 1, -1)),
                NavmeshFixture.Triangle(
                    vertices: SIMD3(1, 3, 2), neighbors: SIMD3(-1, -1, 0), flags: noLarge
                )
            ]
        )
        var graph = RuntimeNavigationGraph()
        graph.setCell(.interior(FormID(1)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(1)), navmeshes: [mesh]
        ))
        return graph
    }

    @Test func aLargeActorKeepsOffNoLargeCreatureTriangles() throws {
        var graph = try Self.graph()
        let small = NavigationPathQuery(
            start: SIMD3(1, 1, 0), target: SIMD3(9, 9, 0), capsuleRadius: 0, projectionRadius: 1
        )
        let large = NavigationPathQuery(
            start: SIMD3(1, 1, 0), target: SIMD3(9, 9, 0), capsuleRadius: 0,
            projectionRadius: 1, largeActor: true
        )
        #expect(Self.found(graph.findPath(small)))
        #expect(!Self.found(graph.findPath(large)))
    }

    @Test func spotsComeNearestFirstAndSkipClosedTriangles() throws {
        let graph = try Self.graph()
        let all = graph.spots(near: SIMD3(9, 9, 0), within: 20, largeActor: false)
        let large = graph.spots(near: SIMD3(9, 9, 0), within: 20, largeActor: true)
        #expect(all.count == 2)
        #expect(try simd_distance(#require(all.first), SIMD3(9, 9, 0)) < 0.001)
        #expect(large.count == 1)
        #expect(graph.spots(near: SIMD3(100, 100, 0), within: 5, largeActor: false).isEmpty)
    }
}
