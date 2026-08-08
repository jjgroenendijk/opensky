// Runtime navmesh graph, projection, deterministic A*, door traversal and
// bounded repathing over synthetic in-code geometry (issue #200).

@testable import opensky
import simd
import Testing

@MainActor
struct NavigationRuntimeTests {
    @Test
    func projectsFeetOntoTrianglePlaneAndReportsBoundedMisses() throws {
        let slope = try NavigationRuntimeFixture.navmesh(
            id: 0x100,
            vertices: [SIMD3(0, 0, 0), SIMD3(10, 0, 10), SIMD3(0, 10, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))]
        )
        let degenerate = try NavigationRuntimeFixture.navmesh(
            id: 0x101,
            vertices: [SIMD3(50, 0, 0), SIMD3(51, 0, 0), SIMD3(52, 0, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))]
        )
        var graph = RuntimeNavigationGraph()
        graph.setCell(.interior(FormID(1)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(1)), navmeshes: [slope, degenerate]
        ))

        let projection = try #require(graph.projection(
            of: SIMD3(5, 2, 20), searchRadius: 20
        ).hit)
        #expect(abs(projection.position.x - 5) < 0.001)
        #expect(abs(projection.position.y - 2) < 0.001)
        #expect(abs(projection.position.z - 5) < 0.001)
        #expect(graph.projection(of: SIMD3(51, 0, 0), searchRadius: 1) == .miss)
        #expect(graph.projection(of: SIMD3(500, 500, 0), searchRadius: 5) == .miss)
    }

    @Test
    func gridPathIsDeterministicAndCarriesQueryStats() throws {
        let mesh = try NavigationRuntimeFixture.grid(id: 0x100, columns: 2, rows: 2)
        var graph = RuntimeNavigationGraph()
        graph.setCell(.interior(FormID(1)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(1)), navmeshes: [mesh]
        ))
        let query = NavigationPathQuery(
            start: SIMD3(1, 1, 2),
            target: SIMD3(19, 19, 2),
            capsuleRadius: 2,
            projectionRadius: 5
        )
        #expect(graph.triangleCount == 8)
        #expect(graph.projection(of: query.start, searchRadius: 5) != .miss)

        let first = graph.findPath(query)
        let second = graph.findPath(query)
        #expect(first == second)
        let path = try #require(first.path)
        let firstWaypoint = try #require(path.waypoints.first)
        let lastWaypoint = try #require(path.waypoints.last)
        #expect(simd_distance(firstWaypoint, SIMD3(1, 1, 0)) < 0.001)
        #expect(simd_distance(lastWaypoint, SIMD3(19, 19, 0)) < 0.001)
        #expect(path.stats.nodesExpanded > 0)
        #expect(path.stats.corridorTriangleCount >= 3)
        #expect(path.doorCrossings.isEmpty)
    }

    @Test
    func funnelShrinksPortalByCapsuleRadius() throws {
        let mesh = try NavigationRuntimeFixture.grid(id: 0x100, columns: 1, rows: 1)
        var graph = RuntimeNavigationGraph()
        graph.setCell(.interior(FormID(1)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(1)), navmeshes: [mesh]
        ))
        let start = SIMD3<Float>(9, 0.5, 0)
        let target = SIMD3<Float>(9.5, 1.5, 0)
        let unshrunk = try #require(graph.findPath(NavigationPathQuery(
            start: start, target: target, capsuleRadius: 0, projectionRadius: 1
        )).path)
        let shrunk = try #require(graph.findPath(NavigationPathQuery(
            start: start, target: target, capsuleRadius: 2, projectionRadius: 1
        )).path)

        #expect(unshrunk.waypoints.count == 2)
        #expect(simd_distance(unshrunk.waypoints[0], start) < 0.001)
        #expect(simd_distance(unshrunk.waypoints[1], target) < 0.001)
        #expect(shrunk.waypoints.count == 3)
        let clearanceWaypoint = try #require(shrunk.waypoints.dropFirst().first)
        #expect(abs(simd_distance(clearanceWaypoint, SIMD3(10, 0, 0)) - 2) < 0.001)
    }

    @Test
    func crossCellLinkExistsOnlyWhileBothCellsAreResident() throws {
        let fixture = try Self.crossCellFixture()
        var graph = RuntimeNavigationGraph()
        graph.setCell(fixture.firstLocation, scene: fixture.firstScene)
        graph.setCell(fixture.secondLocation, scene: fixture.secondScene)
        let query = Self.crossCellQuery
        #expect(graph.triangleCount == 2)
        #expect(graph.projection(of: query.start, searchRadius: 2) != .miss)

        let path = try #require(graph.findPath(query).path)
        #expect(path.stats.corridorTriangleCount == 2)
        #expect(graph.pathIsCurrent(path, target: query.target))
        #expect(!graph.pathIsCurrent(
            path,
            target: query.target + SIMD3(10, 0, 0),
            targetMoveTolerance: 5
        ))

        graph.removeCell(fixture.secondLocation)
        #expect(!graph.pathIsCurrent(path, target: query.target))
        #expect(graph.findPath(query) == .miss(.targetProjection))
    }

    @Test
    func teleportDoorProducesCrossingAndWaypoints() throws {
        let sourcePosition = SIMD3<Float>(2, 2, 0)
        let destinationPosition = SIMD3<Float>(102, 2, 0)
        let source = try Self.doorMesh(
            id: 0x100, offset: 0, door: 0xA00
        )
        let destination = try Self.doorMesh(
            id: 0x200, offset: 100, door: 0xB00
        )
        var graph = RuntimeNavigationGraph()
        graph.setCell(.interior(FormID(1)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(1)),
            navmeshes: [source],
            doors: [NavigationRuntimeFixture.placedDoor(
                reference: 0xA00, destination: 0xB00, position: sourcePosition
            )],
            interactions: [FormID(0xA00): NavigationRuntimeFixture.doorInteraction(
                reference: 0xA00, position: sourcePosition
            )]
        ))
        graph.setCell(.interior(FormID(2)), scene: NavigationRuntimeFixture.scene(
            location: .interior(FormID(2)),
            navmeshes: [destination],
            doors: [NavigationRuntimeFixture.placedDoor(
                reference: 0xB00, destination: 0xA00, position: destinationPosition
            )],
            interactions: [FormID(0xB00): NavigationRuntimeFixture.doorInteraction(
                reference: 0xB00, position: destinationPosition
            )]
        ))

        let path = try #require(graph.findPath(NavigationPathQuery(
            start: SIMD3(1, 1, 0), target: SIMD3(101, 1, 0), capsuleRadius: 0
        )).path)
        let crossing = try #require(path.doorCrossings.first)
        #expect(crossing.door == FormID(0xA00))
        #expect(path.waypoints[crossing.waypointIndex] == sourcePosition)
        #expect(path.waypoints.contains(destinationPosition))
    }

    @Test
    func unloadInvalidationQueuesOnlyBoundedRepaths() throws {
        let fixture = try Self.crossCellFixture()
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 1)
        streamer.composition.setCell(fixture.firstScene, at: CellCoordinate(x: 0, y: 0))
        streamer.composition.setCell(fixture.secondScene, at: CellCoordinate(x: 1, y: 0))
        let path = try #require(streamer.findPath(Self.crossCellQuery).path)
        streamer.composition.removeCell(at: CellCoordinate(x: 1, y: 0))
        #expect(!streamer.navigationPathIsCurrent(path, target: Self.crossCellQuery.target))

        var responses: [NavigationRepathResponse] = []
        streamer.navigationState.onRepath = { responses.append($0) }
        for identifier in 1 ... 3 {
            streamer.requestNavigationRepath(NavigationRepathRequest(
                identifier: UInt64(identifier), query: Self.crossCellQuery
            ))
        }
        streamer.advanceNavigation()

        #expect(responses.map(\.identifier) == [1, 2])
        #expect(streamer.navigationState.repathRequests.map(\.identifier) == [3])
    }

    private static let crossCellQuery = NavigationPathQuery(
        start: SIMD3(1, 1, 0),
        target: SIMD3(9, 9, 0),
        capsuleRadius: 0,
        projectionRadius: 2
    )

    private static func crossCellFixture() throws -> NavigationCrossCellFixture {
        let first = try NavigationRuntimeFixture.navmesh(
            id: 0x100,
            vertices: [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0)],
            triangles: [NavmeshFixture.Triangle(
                vertices: SIMD3(0, 1, 2),
                neighbors: SIMD3(-1, 0, -1),
                flags: NavmeshGeometry.TriangleFlags.edge12Link.rawValue
            )],
            edgeLinks: [NavmeshFixture.EdgeLink(navmesh: 0x200, triangle: 0)]
        )
        let second = try NavigationRuntimeFixture.navmesh(
            id: 0x200,
            vertices: [SIMD3(10, 0, 0), SIMD3(10, 10, 0), SIMD3(0, 10, 0)],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))]
        )
        let firstLocation = CellSceneLocation.exterior(CellCoordinate(x: 0, y: 0))
        let secondLocation = CellSceneLocation.exterior(CellCoordinate(x: 1, y: 0))
        return NavigationCrossCellFixture(
            firstLocation: firstLocation,
            firstScene: NavigationRuntimeFixture.scene(
                location: firstLocation, navmeshes: [first]
            ),
            secondLocation: secondLocation,
            secondScene: NavigationRuntimeFixture.scene(
                location: secondLocation, navmeshes: [second]
            )
        )
    }

    private static func doorMesh(id: UInt32, offset: Float, door: UInt32) throws -> Navmesh {
        try NavigationRuntimeFixture.navmesh(
            id: id,
            vertices: [
                SIMD3(offset, 0, 0), SIMD3(offset + 10, 0, 0), SIMD3(offset, 10, 0)
            ],
            triangles: [NavmeshFixture.Triangle(vertices: SIMD3(0, 1, 2))],
            doorLinks: [NavmeshFixture.DoorLink(triangle: 0, door: door)]
        )
    }
}

private struct NavigationCrossCellFixture {
    let firstLocation: CellSceneLocation
    let firstScene: CellScene
    let secondLocation: CellSceneLocation
    let secondScene: CellScene
}

extension NavigationProjectionResult {
    fileprivate var hit: NavigationProjection? {
        guard case let .hit(projection) = self else { return nil }
        return projection
    }
}

extension NavigationPathResult {
    fileprivate var path: NavigationPath? {
        guard case let .path(path) = self else { return nil }
        return path
    }
}
