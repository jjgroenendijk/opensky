// A path start or target above the navmesh lands on the triangle straight below it.

@testable import OpenSkyCells
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyNavigation
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
struct NavigationDropTests {
    @Test
    func aStartHighAboveTheNavmeshPathsFromTheTriangleBelow() throws {
        let mesh = try NavigationRuntimeFixture.grid(id: 0x100, columns: 2, rows: 2)
        var graph = RuntimeNavigationGraph()
        graph.setCell(.interior(FormID(1)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(1)), navmeshes: [mesh]
        ))
        let query = NavigationPathQuery(start: SIMD3(1, 1, 3000), target: SIMD3(19, 19, 2))

        let firstWaypoint = try #require(Self.waypoints(graph.findPath(query)).first)
        #expect(simd_distance(firstWaypoint, SIMD3(1, 1, 0)) < 0.001)
        #expect(graph.dropProjection(of: SIMD3(1, 1, -5)) == nil)
        #expect(graph.dropProjection(of: SIMD3(500, 500, 10)) == nil)
        let high = NavigationPathQuery(start: SIMD3(1, 1, 2), target: SIMD3(19, 19, 3000))
        let lastWaypoint = try #require(Self.waypoints(graph.findPath(high)).last)
        #expect(simd_distance(lastWaypoint, SIMD3(19, 19, 0)) < 0.001)
        let miss = NavigationPathQuery(start: SIMD3(500, 500, 3000), target: SIMD3(19, 19, 2))
        #expect(graph.findPath(miss) == .miss(.startProjection))
        let away = NavigationPathQuery(start: SIMD3(1, 1, 2), target: SIMD3(500, 500, 3000))
        #expect(graph.findPath(away) == .miss(.targetProjection))
    }

    private static func waypoints(_ result: NavigationPathResult) -> [SIMD3<Float>] {
        guard case let .path(path) = result else { return [] }
        return path.waypoints
    }
}
