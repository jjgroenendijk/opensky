// NPC locomotion on the real install. Timings are printed into the run; no
// game bytes or frames leave it.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
struct NPCMovementRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot), .tags(.perf, .slow))
    func measuresVanillaGraphsAtMoverCap() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let graphs = try (0 ..< NPCMovementRuntime.maximumSimultaneousMovers).map { _ in
            try PlayerBehaviorGraph.load(fileSystem: fileSystem).instance
        }
        let frames = 240
        let started = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< frames {
            for graph in graphs {
                _ = graph.update(deltaTime: 1 / 60)
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        let millisecondsPerFrame = elapsed / Double(frames)
        #expect(millisecondsPerFrame.isFinite)
        #expect(millisecondsPerFrame > 0)
        let kinematic = Self.measureKinematicMovers(frames: frames)
        #expect(kinematic < NPCMovementRuntime.maximumCPUTimeMillisecondsAtCap)
        print(
            "[INFO] \(graphs.count) vanilla NPC graphs: "
                + "\(millisecondsPerFrame) ms/frame over \(frames) frames; "
                + "kinematic movers: \(kinematic) ms/frame"
        )
    }

    private static func measureKinematicMovers(frames: Int) -> Double {
        let path = NavigationPath(
            waypoints: [SIMD3(0, 0, 0), SIMD3(100_000, 0, 0)],
            doorCrossings: [],
            stats: NavigationPathStats(nodesExpanded: 1, corridorTriangleCount: 1),
            corridor: [],
            cellSequences: [:],
            target: SIMD3(100_000, 0, 0)
        )
        var runtime = NPCMovementRuntime()
        for index in 0 ..< NPCMovementRuntime.maximumSimultaneousMovers {
            _ = runtime.start(NPCMoveStart(
                actor: .plugin(name: "measurement.esm", objectID: UInt32(index + 1)),
                formID: FormID(UInt32(index + 1)),
                placement: PlacedReference.Placement(position: .zero, rotation: .zero),
                scale: 1,
                capsule: .standard,
                configuration: .synthetic,
                path: path
            ))
        }
        let world = NPCMovementWorld(
            sampleGround: { _ in TerrainGroundSample(height: 0, normal: SIMD3(0, 0, 1)) },
            collisionQuery: { _ in [] },
            repath: { _ in .miss(.disconnected) },
            cellAt: { _ in .exterior(CellCoordinate(x: 0, y: 0)) },
            triggersAt: { _ in [] }
        )
        let started = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< frames {
            runtime.advance(by: 1 / 60, world: world)
        }
        return Double(DispatchTime.now().uptimeNanoseconds - started)
            / 1_000_000 / Double(frames)
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func walksChillfurrowExteriorToInteriorOffscreen() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        var route = try RealNavigationFixture.route(root: root)
        let result = route.graph.findPath(NavigationPathQuery(
            start: route.start, target: route.target
        ))
        let path = try #require(result.path, "real exterior-to-interior path missed")
        #expect(path.doorCrossings.map(\.door) == [WalkPathRoute.farmDoor])

        var runtime = NPCMovementRuntime()
        let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x423)
        let started = runtime.start(NPCMoveStart(
            actor: actor,
            formID: FormID(0x423),
            placement: PlacedReference.Placement(
                position: path.waypoints[0], rotation: .zero
            ),
            scale: 1,
            capsule: .standard,
            configuration: PlayerMovementConfiguration.resolve(
                store: GameSettingLoader.load(root: root),
                movementTypes: MovementTypeLoader.load(root: root)
            ),
            path: path
        ))
        #expect(started)
        var doorCrossings: [FormID] = []
        runtime.onDoorCrossing = { _, door in doorCrossings.append(door) }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let world = RealNavigationFixture.movementWorld(path: path, graph: route.graph)
        for _ in 0 ..< 2400 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 1 / 60, world: world)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        let readout = try #require(runtime.readouts().first)
        #expect(readout.state == .arrived)
        #expect(doorCrossings == [WalkPathRoute.farmDoor])
        #expect(readout.feetPosition.x.isFinite && readout.feetPosition.y.isFinite)
        print(
            "[INFO] Chillfurrow NPC route: \(path.waypoints.count) waypoints, "
                + "\(path.stats.corridorTriangleCount) triangles, \(elapsed) ms offscreen"
        )
    }
}

extension NavigationPathResult {
    fileprivate var path: NavigationPath? {
        guard case let .path(path) = self else { return nil }
        return path
    }
}
