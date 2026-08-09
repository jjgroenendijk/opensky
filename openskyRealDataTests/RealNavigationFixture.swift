// The real-install exterior-to-interior navigation route, shared by the item
// 16.4 evidence suite and the M16 gate (issues #423 and #203).
//
// Extracted from `NPCMovementRealDataTests` when the gate needed the same two
// cells: a route located twice from two copies of the same CELL walk is a route
// that can quietly become two different routes, and the whole point of the M16
// gate reusing 16.4's is that it is the same corridor.
//
// Reads the user's own install in place. No bytes, geometry, or positions from
// it are committed — this file locates records by FormID and hands back live
// values (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd
import Testing

/// One located cell's children group, which is all the navmesh collector needs.
struct RealLocatedCell {
    let children: ESMGroup
}

/// The Chillfurrow Farm route: the exterior cell, the interior cell, and the
/// paired door between them.
struct RealNavigationRoute {
    /// `var` because `findPath` reconciles and remembers as it queries.
    var graph: RuntimeNavigationGraph
    let exteriorDoor: PlacedReference
    /// Where a walk starts, on the exterior side.
    let start: SIMD3<Float>
    /// Where it ends, 96 units inside the farmhouse.
    let target: SIMD3<Float>
}

@MainActor
enum RealNavigationFixture {
    /// Builds the two-cell graph and the two ends of the route.
    static func route(root: GameDataRoot) throws -> RealNavigationRoute {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let exterior = try #require(exteriorFarmCell(in: file, localized: localized))
        let interior = try #require(interiorFarmCell(in: file, localized: localized))
        let exteriorDoor = try door(WalkPathRoute.farmDoor, in: file)
        let interiorDoor = try door(WalkPathRoute.interiorDoor, in: file)

        var graph = RuntimeNavigationGraph()
        graph.setCell(.exterior(WalkPathRoute.farmCell), scene: scene(
            location: .exterior(WalkPathRoute.farmCell), cell: exterior, door: exteriorDoor
        ))
        graph.setCell(.interior(WalkPathRoute.farmInterior), scene: scene(
            location: .interior(WalkPathRoute.farmInterior), cell: interior, door: interiorDoor
        ))
        let arrival = try #require(exteriorDoor.teleportDestination).placement
        let target = arrival.position + SIMD3(
            cosf(arrival.rotation.z), sinf(arrival.rotation.z), 0
        ) * 96
        return RealNavigationRoute(
            graph: graph,
            exteriorDoor: exteriorDoor,
            start: SIMD3(WalkPathRoute.exteriorReturn, exteriorDoor.placement.position.z),
            target: target
        )
    }

    /// The mover's world over one located path: ground sampled from the
    /// corridor's own waypoints, nothing in the way, and the real graph's cell
    /// answer so the door hand-off is produced rather than announced.
    static func movementWorld(
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

    // MARK: - Locating

    static func exteriorFarmCell(in file: ESMFile, localized: Bool) -> RealLocatedCell? {
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

    static func interiorFarmCell(in file: ESMFile, localized: Bool) -> RealLocatedCell? {
        guard let top = file.topGroup(of: "CELL") else { return nil }
        return findCell(in: top, localized: localized) {
            $0.formID == WalkPathRoute.farmInterior
        }
    }

    static func findCell(
        in group: ESMGroup,
        localized: Bool,
        matches: (Cell) -> Bool
    ) -> RealLocatedCell? {
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
                return RealLocatedCell(children: cellChildren)
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

    static func door(_ formID: FormID, in file: ESMFile) throws -> PlacedReference {
        let record = try #require(ESMWalk.record(withFormID: formID.rawValue, in: file))
        return try PlacedReference(record: record)
    }

    static func scene(
        location: CellSceneLocation,
        cell: RealLocatedCell,
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
}
