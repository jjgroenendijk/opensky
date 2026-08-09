// Real-install NPC locomotion evidence (issue #423). No game bytes or frames
// leave the read-only install; timings are printed into the realtest run.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct NPCMovementRealDataTests {
    nonisolated private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func measuresVanillaGraphsAtMoverCap() throws {
        let root = try #require(Self.dataRoot)
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

    @Test(.enabled(if: Self.dataRoot != nil))
    func walksChillfurrowExteriorToInteriorOffscreen() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let exterior = try #require(Self.exteriorFarmCell(in: file, localized: localized))
        let interior = try #require(Self.interiorFarmCell(in: file, localized: localized))
        let exteriorDoor = try Self.door(WalkPathRoute.farmDoor, in: file)
        let interiorDoor = try Self.door(WalkPathRoute.interiorDoor, in: file)

        var graph = RuntimeNavigationGraph()
        graph.setCell(.exterior(WalkPathRoute.farmCell), scene: Self.scene(
            location: .exterior(WalkPathRoute.farmCell),
            cell: exterior,
            door: exteriorDoor
        ))
        graph.setCell(.interior(WalkPathRoute.farmInterior), scene: Self.scene(
            location: .interior(WalkPathRoute.farmInterior),
            cell: interior,
            door: interiorDoor
        ))
        let arrival = try #require(exteriorDoor.teleportDestination).placement
        let target = arrival.position + SIMD3(
            cosf(arrival.rotation.z), sinf(arrival.rotation.z), 0
        ) * 96
        let result = graph.findPath(NavigationPathQuery(
            start: SIMD3(WalkPathRoute.exteriorReturn, exteriorDoor.placement.position.z),
            target: target
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
        for _ in 0 ..< 2400 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 1 / 60, world: Self.world(path: path, graph: graph))
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

    private struct LocatedCell {
        let children: ESMGroup
    }

    private static func exteriorFarmCell(
        in file: ESMFile,
        localized: Bool
    ) -> LocatedCell? {
        guard let top = file.topGroup(of: "WRLD"), let children = try? top.children() else {
            return nil
        }
        var tamriel: UInt32?
        for child in children {
            switch child {
            case let .record(record) where record.type == "WRLD":
                let world = try? Worldspace(record: record, localized: localized)
                tamriel = world?.editorID == FirstRenderCell.worldspaceEditorID
                    ? record.formID : nil
            case let .group(group)
                where group.kind == .worldChildren && group.parentFormID == tamriel:
                return findCell(in: group, localized: localized) { cell in
                    cell.grid.map {
                        $0.x == WalkPathRoute.farmCell.x && $0.y == WalkPathRoute.farmCell.y
                    } ?? false
                }
            default:
                break
            }
        }
        return nil
    }

    private static func interiorFarmCell(
        in file: ESMFile,
        localized: Bool
    ) -> LocatedCell? {
        guard let top = file.topGroup(of: "CELL") else { return nil }
        return findCell(in: top, localized: localized) {
            $0.formID == WalkPathRoute.farmInterior
        }
    }

    private static func findCell(
        in group: ESMGroup,
        localized: Bool,
        matches: (Cell) -> Bool
    ) -> LocatedCell? {
        guard let children = try? group.children() else { return nil }
        for (index, child) in children.enumerated() {
            switch child {
            case let .record(record) where record.type == "CELL":
                guard
                    let cell = try? Cell(record: record, localized: localized),
                    matches(cell),
                    children.indices.contains(index + 1),
                    case let .group(cellChildren) = children[index + 1],
                    cellChildren.kind == .cellChildren,
                    cellChildren.parentFormID == record.formID
                else { continue }
                return LocatedCell(children: cellChildren)
            case let .group(nested):
                if let found = findCell(in: nested, localized: localized, matches: matches) {
                    return found
                }
            default:
                break
            }
        }
        return nil
    }

    private static func door(_ formID: FormID, in file: ESMFile) throws -> PlacedReference {
        let record = try #require(ESMWalk.record(withFormID: formID.rawValue, in: file))
        return try PlacedReference(record: record)
    }

    private static func scene(
        location: CellSceneLocation,
        cell: LocatedCell,
        door: PlacedReference
    ) -> CellScene {
        let placed = door.teleportDestination.map {
            PlacedDoor(reference: door.formID, position: door.placement.position, destination: $0)
        }
        return CellStreamerTests.cellScene(
            location: location,
            doors: placed.map { [$0] } ?? [],
            navmeshes: CellSceneBuilder.collectNavmeshes(in: cell.children)
        )
    }

    private static func world(
        path: NavigationPath,
        graph: RuntimeNavigationGraph
    ) -> NPCMovementWorld {
        NPCMovementWorld(
            sampleGround: { position in
                let nearest = path.waypoints.min {
                    simd_distance_squared(SIMD2($0.x, $0.y), position)
                        < simd_distance_squared(SIMD2($1.x, $1.y), position)
                }
                return nearest.map {
                    TerrainGroundSample(height: $0.z, normal: SIMD3(0, 0, 1))
                }
            },
            collisionQuery: { _ in [] },
            repath: { _ in .miss(.disconnected) },
            cellAt: { graph.cell(at: $0) },
            triggersAt: { _ in [] }
        )
    }
}

extension NavigationPathResult {
    fileprivate var path: NavigationPath? {
        guard case let .path(path) = self else { return nil }
        return path
    }
}
